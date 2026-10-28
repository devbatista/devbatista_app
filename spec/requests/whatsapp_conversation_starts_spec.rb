require "rails_helper"

RSpec.describe "WhatsApp → iniciar conversa e cards no CRM" do
  let(:admin) { create(:user, :admin, name: "Rafael Batista") }
  let(:reader) { create(:user, role: create(:role, permissions: { "whatsapp" => "read", "comercial" => "read", "clientes" => "read" })) }
  let!(:account) { create(:whatsapp_account, status: "connected") }
  let!(:template) { create(:whatsapp_template, account: account, name: "retomada_contato", components: [ { "type" => "BODY", "text" => "Olá, {{1}}! Sobre {{2}}." } ]) }
  let(:now) { Time.zone.parse("2026-10-28 11:24") }

  around { |example| travel_to(now) { example.run } }

  def start(recipient, values: [ "Henrique", "o seu projeto" ], **extra)
    key = recipient.is_a?(Lead) ? :lead_id : :contact_id
    post whatsapp_conversation_start_path, params: { key => recipient.id, conta: account.id, template_id: template.id, values: { body: values } }.merge(extra)
  end

  def defaults_in(body)
    JSON.parse(CGI.unescapeHTML(body[/data-whatsapp-template-fields-templates-value="([^"]*)"/, 1])).map { |t| t["defaults"]["body"] }
  end

  describe "Nova conversa" do
    before { sign_in admin }

    it "lista só leads e contatos com WhatsApp e busca por nome, empresa e telefone" do
      create(:lead, name: "Henrique Duarte", company_name: "Grupo Norte", whatsapp: "(11) 99102-3344")
      create(:lead, name: "Sem Número", whatsapp: nil)
      contact = create(:contact, name: "Paulo Reis", company: create(:company, trade_name: "Empresa ACME"), whatsapp: "(11) 97654-1122")

      get whatsapp_conversations_path
      expect(response.body).to include("Nova conversa", new_whatsapp_conversation_start_path)

      get new_whatsapp_conversation_start_path, headers: { "Turbo-Frame" => "drawer-frame" }
      expect(response.body).to include("Grupo Norte", "Paulo Reis", new_whatsapp_conversation_start_path(contact_id: contact.id)).and(exclude("Sem Número"))

      get new_whatsapp_conversation_start_path(q: "acme"), headers: { "Turbo-Frame" => "drawer-frame" }
      expect(response.body).to include("Paulo Reis").and(exclude("Grupo Norte"))
      get new_whatsapp_conversation_start_path(q: "99102"), headers: { "Turbo-Frame" => "drawer-frame" }
      expect(response.body).to include("Grupo Norte").and(exclude("Paulo Reis"))
    end
  end

  describe "iniciar" do
    before { sign_in admin }

    let(:lead) { create(:lead, name: "Henrique Duarte", company_name: "Grupo Norte", whatsapp: "(11) 99102-3344") }

    it "abre o formulário com o template e o {{1}} já com o primeiro nome" do
      get new_whatsapp_conversation_start_path(lead_id: lead.id), headers: { "Turbo-Frame" => "drawer-frame" }

      expect(response.body).to include("Iniciar conversa no WhatsApp", "Para <b class=\"strong\">Henrique Duarte</b> · Grupo Norte", "(11) 99102-3344",
                                       "retomada_contato", "Enviar template")
      expect(defaults_in(response.body)).to eq([ [ "Henrique", nil ] ])
    end

    it "cria a conversa pelo número, envia o template e liga a conversa ao lead" do
      expect { start(lead) }.to change(WhatsappConversation, :count).by(1).and have_enqueued_job(WhatsappSendJob)

      conversation = WhatsappConversation.last
      expect(response).to redirect_to(whatsapp_conversation_path(conversation))
      expect(flash[:notice]).to eq("Template enviado para Henrique Duarte.")
      expect(conversation).to have_attributes(account: account, wa_id: "5511991023344", lead: lead, linked_by: admin)
      expect(conversation.messages.sole).to have_attributes(kind: "template", status: "pending", template_name: "retomada_contato",
                                                            body: "Olá, Henrique! Sobre o seu projeto.", user: admin)
    end

    it "usa a conversa que já existe com o número sem o nono dígito" do
      existing = create(:whatsapp_conversation, account: account, wa_id: "551191023344", bsuid: "BR.1", last_message_at: 2.days.ago)

      expect { start(lead) }.not_to change(WhatsappConversation, :count)

      expect(response).to redirect_to(whatsapp_conversation_path(existing))
      expect(existing.reload).to have_attributes(lead: lead, wa_id: "551191023344")
      expect(existing.messages.sole.kind).to eq("template")
    end

    it "recusa o número que já está numa conversa ligada a outro cadastro" do
      other = create(:contact, name: "Juliana Ferraz")
      create(:whatsapp_conversation, account: account, wa_id: "5511991023344", contact: other)

      expect { start(lead) }.not_to change(WhatsappMessage, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("O número (11) 99102-3344 já está na conversa com Juliana Ferraz. Abra a conversa para enviar.")
    end

    it "sem o número no cadastro, pede o número e salva no lead" do
      lead.update!(whatsapp: nil)

      get new_whatsapp_conversation_start_path(lead_id: lead.id)
      expect(response.body).to include("Henrique não tem WhatsApp cadastrado", 'name="numero"', "Salvar no cadastro do lead")

      start(lead, numero: "11 9876")
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Informe o WhatsApp de Henrique com DDD")

      start(lead, numero: "(11) 98765-4321", salvar_numero: "1")
      expect(WhatsappConversation.last).to have_attributes(wa_id: "5511987654321", lead: lead)
      expect(lead.reload.whatsapp).to eq("(11) 98765-4321")
    end

    it "com variável em branco, não cria a conversa e devolve o formulário com o que foi digitado" do
      expect { start(lead, values: [ "Henrique", "" ]) }.not_to change(WhatsappConversation, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Preencha todas as variáveis do template.")
      expect(defaults_in(response.body)).to eq([ [ "Henrique", "" ] ])
    end

    it "com erro no template, não apaga a conversa que o webhook criou no mesmo instante" do
      raced = nil
      allow(WhatsappConversation).to receive(:locate!).and_wrap_original do |original, *args, **kwargs|
        # Entre a busca do número e o locate!, chega a mensagem do contato pelo webhook.
        raced = create(:whatsapp_conversation, account: account, wa_id: "5511991023344", bsuid: "BR.2", last_message_at: 1.minute.ago)
        create(:whatsapp_message, conversation: raced, body: "Oi, quem fala?", sent_at: 1.minute.ago)
        original.call(*args, **kwargs)
      end

      start(lead, values: [ "Henrique", "" ])

      expect(response).to have_http_status(:unprocessable_content)
      expect(WhatsappConversation.where(id: raced.id)).to exist
      expect(raced.messages.pluck(:body)).to eq([ "Oi, quem fala?" ])
    end

    it "recusa também quando a conversa criada no mesmo instante já está ligada a outro cadastro" do
      other = create(:contact, name: "Juliana Ferraz")
      allow(WhatsappConversation).to receive(:locate!).and_wrap_original do |original, *args, **kwargs|
        create(:whatsapp_conversation, account: account, wa_id: "5511991023344", bsuid: "BR.3", contact: other)
        original.call(*args, **kwargs)
      end

      expect { start(lead) }.not_to change(WhatsappMessage, :count)

      expect(response.body).to include("já está na conversa com Juliana Ferraz")
      expect(WhatsappConversation.find_by!(wa_id: "5511991023344").contact).to eq(other)
    end

    it "inicia com o contato, ligando a conversa a ele" do
      contact = create(:contact, name: "Paulo Reis", whatsapp: "+55 11 97654-1122")
      start(contact, values: [ "Paulo", "a proposta" ])
      expect(WhatsappConversation.last).to have_attributes(wa_id: "5511976541122", contact: contact, lead: nil)
    end
  end

  describe "valores sugeridos no campo de envio da conversa" do
    it "preenche o {{1}} com o primeiro nome do lead vinculado, ou do perfil sem vínculo" do
      sign_in admin
      linked = create(:whatsapp_conversation, account: account, lead: create(:lead, name: "Beatriz Toledo"), last_message_at: 1.hour.ago)
      unlinked = create(:whatsapp_conversation, account: account, profile_name: "Lu Martins", last_message_at: 1.hour.ago)

      get whatsapp_conversation_path(linked)
      expect(defaults_in(response.body)).to eq([ [ "Beatriz", nil ] ])
      get whatsapp_conversation_path(unlinked)
      expect(defaults_in(response.body)).to eq([ [ "Lu", nil ] ])
    end
  end

  describe "cards" do
    before { sign_in admin }

    it "no lead: as últimas mensagens e a janela, ou Iniciar conversa, ou o aviso de sem número" do
      lead = create(:lead, name: "Henrique Duarte", whatsapp: "(11) 99102-3344")
      get lead_path(lead)
      expect(response.body).to include("Sem conversa", "Ainda não há conversa com Henrique", "Iniciar conversa no WhatsApp",
                                       new_whatsapp_conversation_start_path(lead_id: lead.id))

      conversation = create(:whatsapp_conversation, account: account, lead: lead, last_message_at: 1.hour.ago, last_inbound_at: 1.hour.ago)
      create(:whatsapp_message, conversation: conversation, body: "Consegue terça?", sent_at: 1.hour.ago)
      create(:whatsapp_message, :outbound, conversation: conversation, body: "Consigo sim", sent_at: 50.minutes.ago, status: "delivered", user: admin)
      get lead_path(lead)
      expect(response.body).to include("Janela aberta · 23h", "Consegue terça?", "Henrique · hoje 10:24", "Consigo sim", "Rafael · hoje 10:34 · Entregue",
                                       "Abrir conversa", whatsapp_conversation_path(conversation))

      other = create(:lead, name: "Sem Número", whatsapp: nil)
      get lead_path(other)
      expect(response.body).to include("Sem número", "o lead não tem <b class=\"strong\">WhatsApp cadastrado</b>", "Editar lead")
    end

    it "na empresa e na lista de contatos: a conversa de cada contato, ou Iniciar conversa" do
      company = create(:company, trade_name: "Empresa ACME")
      juliana = create(:contact, company: company, name: "Juliana Ferraz", whatsapp: "(11) 99812-3344")
      paulo = create(:contact, company: company, name: "Paulo Reis", whatsapp: "(11) 97654-1122")
      conversation = create(:whatsapp_conversation, account: account, contact: juliana, last_message_at: 1.hour.ago, unread_count: 1, preview: "Segue o comprovante")

      get company_path(company)
      expect(response.body).to include("Segue o comprovante", "1 não lida", whatsapp_conversation_path(conversation),
                                       "WhatsApp (11) 97654-1122", new_whatsapp_conversation_start_path(contact_id: paulo.id))

      get contacts_path
      expect(response.body).to include(whatsapp_conversation_path(conversation), new_whatsapp_conversation_start_path(contact_id: paulo.id))
    end
  end

  describe "permissões" do
    it "quem só lê o WhatsApp vê os cards, mas não inicia conversa; sem a área, não vê o card" do
      lead = create(:lead, whatsapp: "(11) 99102-3344")

      sign_in reader
      get lead_path(lead)
      expect(response.body).to include("Sem conversa").and(exclude("Iniciar conversa no WhatsApp"))
      get whatsapp_conversations_path
      expect(response.body).not_to include("Nova conversa")
      get new_whatsapp_conversation_start_path(lead_id: lead.id)
      expect(response).to have_http_status(:forbidden)

      sign_in create(:user, :comercial)
      get lead_path(lead)
      expect(response.body).not_to include("Sem conversa")
    end

    it "quem só lê o WhatsApp não envia" do
      sign_in reader
      lead = create(:lead, whatsapp: "(11) 99102-3344")
      expect { start(lead) }.not_to change(WhatsappConversation, :count)
      expect(response).to have_http_status(:forbidden)
    end
  end
end
