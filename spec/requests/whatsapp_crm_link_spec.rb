require "rails_helper"

RSpec.describe "WhatsApp → vínculo da conversa com o CRM" do
  let(:admin) { create(:user, :admin, name: "Rafael Batista") }
  let(:reader) { create(:user, role: create(:role, permissions: { "whatsapp" => "read" })) }
  let(:account) { create(:whatsapp_account, status: "connected") }
  let(:now) { Time.zone.parse("2026-10-28 11:24") }

  around { |example| travel_to(now) { example.run } }

  def conversation(**attributes)
    create(:whatsapp_conversation, account: account, wa_id: "5511991023344", last_message_at: 1.hour.ago, preview: "Oi", **attributes)
  end

  describe "painel" do
    before { sign_in admin }

    it "mostra o lead: cadastro, etapa, propostas, próximo passo, interações e quem vinculou" do
      lead = create(:lead, name: "Henrique Duarte", company_name: "Grupo Norte Logística", email: "henrique@gruponorte.com.br", status: "qualified",
                           origin: "diagnosis", next_step: "Reunião de plano de trabalho", next_step_on: Date.new(2026, 10, 30), user: admin)
      create(:proposal, lead: lead, title: "Sistema de roteirização")
      create(:interaction, subject: lead, kind: "call", notes: "Confirmou orçamento", user: admin)
      conv = conversation
      conv.link!(lead, user: admin)

      get whatsapp_conversation_path(conv)

      expect(response.body).to include("Grupo Norte Logística", "Lead · Qualificado", "henrique@gruponorte.com.br", "Diagnóstico", "Abrir ficha do lead",
                                       "Sistema de roteirização", "Reunião de plano de trabalho", "30/10/2026", "Confirmou orçamento",
                                       %(id="#{ActionView::RecordIdentifier.dom_id(conv, :panel)}"), "Vinculada por Rafael Batista", "Desvincular conversa")
      expect(response.body).to match(%r{<span class="cur" aria-current="step">Qualificado</span>})
      expect(response.body).to include(new_lead_interaction_path(lead))
    end

    it "mostra o contato com a oportunidade aberta da empresa, e avisa quando não há" do
      contact = create(:contact, name: "Juliana Ferraz", position: "Financeiro")
      opportunity = create(:opportunity, company: contact.company, title: "Novo portal", stage: "proposal")
      conv = conversation(contact: contact)

      get whatsapp_conversation_path(conv)
      expect(response.body).to include("Contato e empresa", contact.company.trade_name, "Juliana Ferraz", "Financeiro", "Abrir Visão 360º", "Novo portal",
                                       new_opportunity_interaction_path(opportunity))

      opportunity.update!(stage: "won")
      get whatsapp_conversation_path(conv)
      expect(response.body).to include("Nenhuma oportunidade aberta com a #{contact.company.trade_name}", "sem interação automática")
    end

    it "sem vínculo, oferece criar e vincular e mostra os cadastros com o mesmo telefone" do
      create(:lead, name: "Lu Martins", company_name: nil, whatsapp: "(11) 99102-3344", status: "lost", lost_reason: "Sem orçamento")
      conv = conversation

      get whatsapp_conversation_path(conv)
      expect(response.body).to include("Conversa sem lead ou contato", "Criar lead", "Vincular a lead/contato existente", "Mesmo telefone", "Lu Martins",
                                       "Lead · Perdido", new_whatsapp_conversation_lead_path(conv), new_whatsapp_conversation_link_path(conv))

      get whatsapp_conversation_path(conversation(wa_id: nil))
      expect(response.body).to include("Sem telefone, não há busca automática")
    end

    it "recarrega só o painel pelo frame" do
      conv = conversation(lead: create(:lead, name: "Henrique Duarte"))
      get panel_whatsapp_conversation_path(conv), headers: { "Turbo-Frame" => ActionView::RecordIdentifier.dom_id(conv, :panel) }
      expect(response.body).to start_with(%(<turbo-frame id="#{ActionView::RecordIdentifier.dom_id(conv, :panel)}")).and include("Henrique Duarte")
    end
  end

  describe "vincular" do
    before { sign_in admin }

    let(:conv) { conversation }

    it "sem busca, lista os cadastros com o telefone; com busca, por nome, empresa e telefone" do
      create(:lead, name: "Luciana Martins", company_name: "Rede Bella Moda", whatsapp: "11 9102-3344")
      contact = create(:contact, name: "Lucas Viana", company: create(:company, trade_name: "Empresa Orion"), whatsapp: "(41) 99660-7731")

      get new_whatsapp_conversation_link_path(conv)
      expect(response.body).to include("Cadastros com o telefone desta conversa", "Rede Bella Moda").and(exclude("Lucas Viana"))

      get new_whatsapp_conversation_link_path(conv, q: "orion"), headers: { "Turbo-Frame" => "drawer-frame" }
      expect(response.body).to include("Lucas Viana", "Contact:#{contact.id}").and(exclude("Rede Bella Moda"))
      get new_whatsapp_conversation_link_path(conv, q: "99660"), headers: { "Turbo-Frame" => "drawer-frame" }
      expect(response.body).to include("Lucas Viana")
      get new_whatsapp_conversation_link_path(conv, q: "ninguém"), headers: { "Turbo-Frame" => "drawer-frame" }
      expect(response.body).to include("Nada encontrado para “ninguém”")
    end

    it "liga ao lead escolhido e salva o telefone no cadastro só quando ele está vazio" do
      lead = create(:lead, name: "Luciana Martins", whatsapp: nil)

      post whatsapp_conversation_link_path(conv), params: { alvo: "Lead:#{lead.id}", salvar_telefone: "1" }

      expect(response).to redirect_to(whatsapp_conversation_path(conv))
      expect(flash[:notice]).to eq("Conversa vinculada ao lead Empresa do lead · Luciana Martins.")
      expect(conv.reload).to have_attributes(lead: lead, contact: nil, linked_by: admin)
      expect(lead.reload.whatsapp).to eq("(11) 99102-3344")

      contact = create(:contact, whatsapp: "(21) 98888-1234")
      post whatsapp_conversation_link_path(conv), params: { alvo: "Contact:#{contact.id}", salvar_telefone: "1" }
      expect(conv.reload).to have_attributes(lead: nil, contact: contact)
      expect(contact.reload.whatsapp).to eq("(21) 98888-1234")
    end

    it "desvincula, marca a conversa e continua mostrando os candidatos; recusa alvo desconhecido" do
      lead = create(:lead, name: "Luciana Martins", company_name: nil, whatsapp: "(11) 99102-3344")
      conv.link!(lead, user: admin)
      delete whatsapp_conversation_link_path(conv)
      expect(response).to redirect_to(whatsapp_conversation_path(conv))
      expect(conv.reload).to have_attributes(lead: nil, linked_at: nil, linked_by: nil, auto_link_blocked_at: be_present)

      get whatsapp_conversation_path(conv)
      expect(response.body).to include("Mesmo telefone", "Luciana Martins", "Lead:#{lead.id}", "o vínculo automático fica desligado até o telefone dela mudar")

      post whatsapp_conversation_link_path(conv), params: { alvo: "User:#{admin.id}" }
      expect(response).to have_http_status(:not_found)
      expect(conv.reload).not_to be_linked
    end
  end

  describe "criar lead" do
    before { sign_in admin }

    let(:conv) { conversation(profile_name: "Lu Martins") }

    it "abre a gaveta com o nome do perfil, o telefone, a origem WhatsApp e as primeiras mensagens" do
      create(:whatsapp_message, conversation: conv, body: "Vocês fazem loja virtual?", sent_at: 2.hours.ago)
      create(:whatsapp_message, conversation: conv, body: "Meu orçamento é até 8 mil.", sent_at: 1.hour.ago)

      get new_whatsapp_conversation_lead_path(conv), headers: { "Turbo-Frame" => "drawer-frame" }

      expect(response.body).to include('value="Lu Martins"', 'value="(11) 99102-3344"', '<option selected="selected" value="whatsapp">WhatsApp</option>',
                                       "Chegou pelo WhatsApp em 28/10/2026: &quot;Vocês fazem loja virtual? Meu orçamento é até 8 mil.&quot;")
    end

    it "cria o lead e vincula a conversa; com erro, não cria nem vincula" do
      params = { lead: { name: "Lu Martins", whatsapp: "(11) 99102-3344", origin: "whatsapp", user_id: admin.id, status: "converted", notes: "Loja virtual" } }

      expect { post whatsapp_conversation_lead_path(conv), params: params }.to change(Lead, :count).by(1)

      lead = Lead.last
      expect(response).to redirect_to(whatsapp_conversation_path(conv))
      expect(lead).to have_attributes(name: "Lu Martins", origin: "whatsapp", status: "new", entered_on: Date.current, user: admin)
      expect(conv.reload).to have_attributes(lead: lead, linked_by: admin)

      other = conversation(wa_id: "5521988881234")
      expect { post whatsapp_conversation_lead_path(other), params: { lead: params[:lead].merge(name: "") } }.not_to change(Lead, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(other.reload).not_to be_linked
    end
  end

  describe "registrar interação pelo painel" do
    before { sign_in admin }

    it "abre na gaveta e volta para a conversa" do
      lead = create(:lead, name: "Henrique Duarte")
      conv = conversation(lead: lead)

      get new_lead_interaction_path(lead), headers: { "Turbo-Frame" => "drawer-frame" }
      expect(response.body).to include("Registrar interação", "Lead · Empresa do lead")

      post lead_interactions_path(lead), params: { interaction: { kind: "meeting", occurred_on: Date.current, notes: "Reunião por vídeo" } },
                                         headers: { "Referer" => whatsapp_conversation_url(conv) }
      expect(response).to redirect_to(whatsapp_conversation_url(conv))
      expect(lead.interactions.sole).to have_attributes(kind: "meeting", notes: "Reunião por vídeo", whatsapp_conversation: nil)
    end
  end

  describe "permissões" do
    it "quem só lê o WhatsApp não vincula, não cria lead e não vê os dados do Comercial" do
      sign_in reader
      lead = create(:lead, name: "Henrique Duarte", email: "henrique@gruponorte.com.br")
      conv = conversation(lead: lead)

      get whatsapp_conversation_path(conv)
      expect(response.body).to include("Os dados do lead ficam no Comercial").and(exclude("henrique@gruponorte.com.br", "Desvincular conversa"))

      unlinked = conversation(wa_id: "5521988881234")
      get whatsapp_conversation_path(unlinked)
      expect(response.body).to exclude("Criar lead", "Vincular a lead/contato existente")

      post whatsapp_conversation_link_path(unlinked), params: { alvo: "Lead:#{lead.id}" }
      expect(response).to have_http_status(:forbidden)
      get new_whatsapp_conversation_lead_path(unlinked)
      expect(response).to have_http_status(:forbidden)
      delete whatsapp_conversation_link_path(conv)
      expect(response).to have_http_status(:forbidden)
      expect(conv.reload.lead).to eq(lead)
    end
  end
end
