require "rails_helper"

RSpec.describe "Webhook de leads do site" do
  let!(:admin) { create(:user, name: "Rafael Batista") }

  let(:diagnosis) do
    { source: "diagnosis", site_id: "a1b2c3d4e5f60718", name: "Ana Souza", company: "Clínica Sorriso", email: "Ana@Clinica.com.br",
      phone: "11987654321", tier: "quente", summary: "Diagnóstico: Alto potencial de otimização (22 pontos) · potencial quente",
      details: "Diagnóstico Tecnológico — 29/10/2026 10:00\nPrincipal desafio: Automatização de tarefas" }
  end

  let(:contact) do
    { source: "contact", site_id: "abc123", name: "Maria Souza", company: "Escritório X", email: "", phone: "11999990000",
      need: "whatsapp_ia", consent: true, summary: "Contato pelo site: Atendimento com IA no WhatsApp · Contabilidade",
      details: "Segmento: Contabilidade\nMensagens por mês: 300 a 1.000" }
  end

  def post_lead(payload, token = "token-do-site-de-teste")
    post "/webhooks/site-leads", params: JSON.generate(payload),
                                 headers: { "Content-Type" => "application/json", "Authorization" => ("Bearer #{token}" if token) }.compact
  end

  it "cria o lead do diagnóstico, sem login, com a interação e o aviso ao responsável" do
    expect { post_lead(diagnosis) }.to change(Lead, :count).by(1).and change(Interaction, :count).by(1)
    expect(response).to have_http_status(:created)

    lead = Lead.find(response.parsed_body["id"])
    expect(lead).to have_attributes(name: "Ana Souza", company_name: "Clínica Sorriso", email: "ana@clinica.com.br", whatsapp: "(11) 98765-4321",
                                    origin: "diagnosis", status: "new", user: admin, external_id: "a1b2c3d4e5f60718", notes: diagnosis[:details])
    expect(lead.interactions.sole).to have_attributes(kind: "note", notes: diagnosis[:summary], user: admin, occurred_on: Date.current)
    expect(admin.notifications.sole).to have_attributes(kind: "site_lead", level: "warn", path: "/commercial/leads/#{lead.id}",
                                                        title: "Novo lead do site: Clínica Sorriso · Ana Souza · potencial quente")
  end

  it "cria o lead do e-book com o e-mail de nome provisório, sem aviso, e o diagnóstico depois completa o mesmo lead" do
    post_lead(source: "ebook", site_id: "e0e0e0e0e0e0e0e0", email: "ana@clinica.com.br", summary: "Baixou o e-book pelo site")
    expect(response).to have_http_status(:created)
    lead = Lead.sole
    expect(lead).to have_attributes(name: "ana@clinica.com.br", origin: "site", company_name: nil, notes: nil)
    expect(Notification.count).to eq(0)

    expect { post_lead(diagnosis) }.not_to change(Lead, :count)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq("id" => lead.id, "created" => false)
    expect(lead.reload).to have_attributes(name: "Ana Souza", company_name: "Clínica Sorriso", whatsapp: "(11) 98765-4321", origin: "site", notes: diagnosis[:details])
    expect(lead.interactions.pluck(:notes)).to contain_exactly("Baixou o e-book pelo site", diagnosis[:summary])
    expect(admin.notifications.sole.title).to eq("Clínica Sorriso · Ana Souza fez o Diagnóstico Tecnológico no site · potencial quente")
  end

  it "não desfaz o que foi editado à mão e soma o diagnóstico novo às observações" do
    lead = create(:lead, name: "Ana S.", company_name: "Sorriso Odonto", email: "ana@clinica.com.br", whatsapp: "(11) 90000-0000", notes: "Indicada pelo Paulo", user: admin)

    post_lead(diagnosis)
    expect(response).to have_http_status(:ok)
    expect(lead.reload).to have_attributes(name: "Ana S.", company_name: "Sorriso Odonto", whatsapp: "(11) 90000-0000",
                                           notes: "Indicada pelo Paulo\n\n#{diagnosis[:details]}")
  end

  it "abre lead novo quando o do mesmo e-mail já foi perdido ou convertido" do
    create(:lead, email: "ana@clinica.com.br", status: "lost", lost_reason: "Preço", user: admin)
    expect { post_lead(diagnosis) }.to change(Lead, :count).by(1)
    expect(response).to have_http_status(:created)
  end

  it "recusa token errado, ausente ou não configurado" do
    [ "outro-token", nil ].each do |token|
      expect { post_lead(diagnosis, token) }.not_to change(Lead, :count)
      expect(response).to have_http_status(:unauthorized)
    end

    allow(Rails.configuration.x.site_leads).to receive(:token).and_return(nil)
    allow(Rails.logger).to receive(:error)
    post_lead(diagnosis, "")
    expect(response).to have_http_status(:unauthorized)
    expect(Rails.logger).to have_received(:error).with(/SITE_LEADS_TOKEN/)
  end

  it "devolve 422 com dados inválidos ou sem administrador para receber" do
    # Lead vazio é o teste de conexão do site (/api/health.php?check=crm): 422 prova que o token passou.
    post_lead([])
    expect(response).to have_http_status(:unprocessable_entity)
    post_lead(diagnosis.merge(email: "sem-arroba"))
    expect(response).to have_http_status(:unprocessable_entity)
    post_lead(diagnosis.merge(source: "outro"))
    expect(response).to have_http_status(:unprocessable_entity)
    post_lead(diagnosis.except(:name))
    expect(response).to have_http_status(:unprocessable_entity)
    post_lead(diagnosis.except(:email))
    expect(response).to have_http_status(:unprocessable_entity)
    post_lead(source: "ebook", site_id: "e0e0e0e0e0e0e0e0", phone: "11987654321")
    expect(response).to have_http_status(:unprocessable_entity)

    admin.update!(active: false)
    post_lead(diagnosis)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["errors"]).to include("Nenhum administrador ativo para receber o lead")
    expect(Lead.count).to eq(0)
  end

  describe "e-mail do aviso ao responsável" do
    let!(:ia) { create(:service, name: "Inteligência Artificial") }

    def mails_to(user) = ActionMailer::Base.deliveries.select { |mail| mail.to == [ user.email ] }
    def html(mail) = mail.html_part.body.decoded
    def text(mail) = mail.text_part.body.decoded

    def post_and_deliver(payload)
      perform_enqueued_jobs(only: ActionMailer::MailDeliveryJob) { post_lead(payload) }
    end

    it "manda o diagnóstico de qualquer potencial, com o nível no assunto e os dados do lead no corpo" do
      post_and_deliver(diagnosis.merge(tier: "frio"))
      mail = mails_to(admin).sole
      lead = Lead.sole

      expect(mail.subject).to eq("[Admin DevBatista] Novo lead do site: Clínica Sorriso · Ana Souza · potencial frio")
      [ html(mail), text(mail) ].each do |body|
        expect(body).to include("Ana Souza", "(11) 98765-4321", "ana@clinica.com.br", "Clínica Sorriso", "Diagnóstico Tecnológico",
                                "Frio", diagnosis[:summary], "Principal desafio: Automatização de tarefas", "/commercial/leads/#{lead.id}")
      end
      expect(html(mail)).to include("https://wa.me/5511987654321", "Potencial frio", "Abrir o lead")
    end

    it "manda todo contato, com o que precisa, o serviço, o segmento e o texto completo" do
      post_and_deliver(contact)
      mail = mails_to(admin).sole

      expect(mail.subject).to eq("[Admin DevBatista] Novo contato do site: Escritório X · Maria Souza")
      [ html(mail), text(mail) ].each do |body|
        expect(body).to include("Maria Souza", "(11) 99999-0000", "Escritório X", "Formulário de contato", "Atendimento com IA no WhatsApp",
                                "Inteligência Artificial", "Segmento", "Contabilidade", "Mensagens por mês: 300 a 1.000",
                                "Consentimento de contato: sim")
      end
      expect(text(mail)).not_to include("E-mail:", "Potencial")
    end

    it "usa o segmento enviado no campo próprio, no lugar da linha do details" do
      post_and_deliver(contact.merge(segment: "Saúde e estética", details: "Caso: agenda lotada"))
      expect(text(mails_to(admin).sole)).to include("Segmento: Saúde e estética")
    end

    it "não avisa o responsável no e-book" do
      post_and_deliver(source: "ebook", site_id: "e0e0e0e0e0e0e0e0", email: "ana@clinica.com.br")
      expect(response).to have_http_status(:created)
      expect(mails_to(admin)).to be_empty
    end

    it "respeita a preferência desligada e o envio de alertas desligado em Configurações" do
      admin.update!(email_preferences: { "site_lead" => false })
      post_and_deliver(contact)
      expect(admin.notifications.count).to eq(1)
      expect(mails_to(admin)).to be_empty

      admin.update!(email_preferences: {})
      Setting[:email_enabled] = false
      post_and_deliver(diagnosis)
      expect(mails_to(admin)).to be_empty
    end

    it "fica ligado por padrão para quem nunca mexeu na preferência" do
      expect(admin.email_for?("site_lead")).to be(true)
    end
  end

  describe "entrega do e-book" do
    let(:ebook) { { source: "ebook", site_id: "e0e0e0e0e0e0e0e0", email: "Ana@Clinica.com.br", summary: "Baixou o e-book pelo site (ebook)" } }

    def ebook_mails = ActionMailer::Base.deliveries.select { |mail| mail.subject == EbookMailer::SUBJECT }

    it "manda ao visitante o link do e-book, do endereço do Rafael e sem Reply-To" do
      perform_enqueued_jobs(only: ActionMailer::MailDeliveryJob) { post_lead(ebook) }
      expect(response).to have_http_status(:created)

      mail = ebook_mails.sole
      expect(mail.to).to eq([ "ana@clinica.com.br" ])
      expect(mail[:from].value).to eq("Rafael Batista <rafael@devbatista.com>")
      expect(mail.reply_to).to be_nil
      expect(mail.subject).to eq("Seu e-book chegou: onde a TI drena o lucro da sua empresa")
      url = "https://www.devbatista.com/materiais/ebook-de-teste.pdf"
      expect(mail.html_part.body.decoded).to include(%(href="#{url}"), "Baixar o e-book (PDF)", "ele chega direto em mim")
      expect(mail.html_part.body.decoded).not_to include("Admin")
      expect(mail.text_part.body.decoded).to include("Obrigado pelo interesse!", url, "Rafael Batista\nDevBatista — devbatista.com")
    end

    it "usa o remetente das variáveis EBOOK_EMAIL_FROM e EBOOK_EMAIL_FROM_NAME" do
      allow(Rails.configuration.x.ebook).to receive_messages(email_from: "materiais@devbatista.com", email_from_name: "DevBatista")
      perform_enqueued_jobs(only: ActionMailer::MailDeliveryJob) { post_lead(ebook) }
      expect(ebook_mails.sole[:from].value).to eq("DevBatista <materiais@devbatista.com>")
    end

    it "manda o e-book de novo a quem pede duas vezes, sem duplicar o lead" do
      perform_enqueued_jobs(only: ActionMailer::MailDeliveryJob) do
        post_lead(ebook)
        expect { post_lead(ebook.merge(site_id: "f1f1f1f1f1f1f1f1")) }.not_to change(Lead, :count)
      end
      expect(response).to have_http_status(:ok)
      expect(ebook_mails.size).to eq(2)
    end

    it "responde 503 ebook_unavailable sem EBOOK_DOWNLOAD_URL, mas guarda o lead" do
      allow(Rails.configuration.x.ebook).to receive(:download_url).and_return(nil)
      allow(Rails.logger).to receive(:error)

      expect { post_lead(ebook) }.not_to have_enqueued_mail(EbookMailer, :download)
      expect(Lead.sole.email).to eq("ana@clinica.com.br")
      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body).to eq("errors" => [ "ebook_unavailable" ])
      expect(Rails.logger).to have_received(:error).with(/EBOOK_DOWNLOAD_URL/)
    end

    it "responde 503 quando o e-mail não entra na fila" do
      allow(Rails.logger).to receive(:error)
      allow(EbookMailer).to receive(:download).and_return(instance_double(ActionMailer::MessageDelivery, deliver_later: false))
      post_lead(ebook)
      expect(response).to have_http_status(:service_unavailable)

      allow(EbookMailer).to receive(:download).and_raise(RuntimeError, "Redis fora do ar")
      post_lead(ebook)
      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body).to eq("errors" => [ "ebook_unavailable" ])
      expect(Rails.logger).to have_received(:error).with(/Redis fora do ar/)
    end
  end

  describe "formulário de contato" do
    let!(:ia) { create(:service, name: "Inteligência Artificial") }

    it "cria o lead sem e-mail, com o serviço da necessidade, a interação, o próximo passo e o aviso ao responsável" do
      travel_to Time.zone.local(2026, 11, 26, 14, 30, 15) do
        expect { post_lead(contact) }.to change(Lead, :count).by(1).and change(Interaction, :count).by(1)
      end
      expect(response).to have_http_status(:created)

      lead = Lead.find(response.parsed_body["id"])
      expect(lead).to have_attributes(name: "Maria Souza", company_name: "Escritório X", email: nil, whatsapp: "(11) 99999-0000",
                                      origin: "site", status: "new", user: admin, external_id: "abc123", service: ia,
                                      notes: "#{contact[:details]}\nConsentimento de contato: sim",
                                      next_step: "Responder o contato do site pelo WhatsApp",
                                      next_step_on: Time.zone.local(2026, 11, 26, 14, 30))
      expect(lead.interactions.sole).to have_attributes(kind: "note", notes: contact[:summary], user: admin)
      expect(admin.notifications.sole).to have_attributes(kind: "site_lead", level: "warn", path: "/commercial/leads/#{lead.id}",
                                                          title: "Novo contato do site: Escritório X · Maria Souza")
    end

    it "usa a nota padrão sem summary e aceita o contato sem consent" do
      post_lead(contact.except(:summary, :consent, :details))
      expect(response).to have_http_status(:created)
      lead = Lead.sole
      expect(lead.interactions.sole.notes).to eq("Enviou o formulário de contato pelo site")
      expect(lead.notes).to be_nil
    end

    it "completa o lead em aberto com o mesmo WhatsApp, sem trocar serviço nem próximo passo já definidos" do
      outro = create(:service, name: "Consultoria")
      lead = create(:lead, name: "Maria", company_name: nil, email: "maria@escritorio.com.br", whatsapp: "(11) 99999-0000", service: outro,
                           next_step: "Ligar na segunda", next_step_on: Date.new(2026, 12, 1), user: admin)

      expect { post_lead(contact) }.not_to change(Lead, :count)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("id" => lead.id, "created" => false)
      expect(lead.reload).to have_attributes(name: "Maria", email: "maria@escritorio.com.br", company_name: "Escritório X", service: outro,
                                             next_step: "Ligar na segunda")
      expect(admin.notifications.sole).to have_attributes(level: "warn", title: "Escritório X · Maria enviou o formulário de contato")
    end

    it "acha o lead pelo e-mail quando vem e-mail, e pelo telefone o mais recente em aberto" do
      by_email = create(:lead, email: "maria@escritorio.com.br", user: admin)
      post_lead(contact.merge(email: "Maria@Escritorio.com.br", phone: "11911112222"))
      expect(response.parsed_body).to eq("id" => by_email.id, "created" => false)

      create(:lead, whatsapp: "(11) 99999-0000", user: admin, created_at: 2.days.ago)
      newest = create(:lead, whatsapp: "(11) 99999-0000", user: admin, created_at: 1.day.ago)
      post_lead(contact)
      expect(response.parsed_body).to eq("id" => newest.id, "created" => false)
    end

    it "abre lead novo quando o do mesmo WhatsApp já foi perdido ou convertido" do
      create(:lead, whatsapp: "(11) 99999-0000", status: "lost", lost_reason: "Preço", user: admin)
      create(:lead, whatsapp: "(11) 99999-0000", status: "converted", user: admin)
      expect { post_lead(contact) }.to change(Lead, :count).by(1)
      expect(response).to have_http_status(:created)
    end

    it "mapeia a necessidade para o serviço do catálogo pelo nome e segue sem serviço quando não há" do
      sob_medida = create(:service, name: "Desenvolvimento de sistemas")
      {
        "whatsapp_ia" => ia, "ia_sistemas" => ia, "sob_medida" => sob_medida,
        "automacao_ia" => nil, # "Automação/RPA" não está no catálogo do teste
        "agencia" => nil, "nao_sei" => nil, "outra_coisa" => nil, nil => nil
      }.each_with_index do |(need, service), index|
        post_lead(contact.merge(need: need, site_id: "need#{index}", phone: "1199999#{index.to_s.rjust(4, '0')}"))
        expect(response).to have_http_status(:created)
        expect(Lead.find(response.parsed_body["id"]).service).to eq(service), "need #{need.inspect}"
      end
    end

    it "recusa contato sem nome, sem telefone ou com e-mail inválido" do
      [ contact.except(:name), contact.merge(phone: ""), contact.merge(email: "sem-arroba") ].each do |payload|
        expect { post_lead(payload) }.not_to change(Lead, :count)
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    it "recusa token errado" do
      expect { post_lead(contact, "outro-token") }.not_to change(Lead, :count)
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
