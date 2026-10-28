require "rails_helper"

RSpec::Matchers.define_negated_matcher :exclude, :include

RSpec.describe "WhatsApp → Templates" do
  let(:admin) { create(:user, :admin) }
  let(:reader) { create(:user, role: create(:role, permissions: { "whatsapp" => "read" })) }
  let!(:account) { create(:whatsapp_account, status: "connected", verified_name: "DevBatista") }
  let(:form) do
    { account_id: account.id, name: "lembrete_proposta", language: "pt_BR", category: "utility", header_type: "",
      body: "Olá, {{1}}. A proposta {{2}} vence amanhã.", body_examples: [ "Beatriz", "Novo site" ], footer: "DevBatista",
      buttons: [ { type: "url", text: "Ver proposta", url: "https://admin.devbatista.com/p/{{1}}", url_example: "https://admin.devbatista.com/p/P-2026-029", phone: "" } ] }
  end

  around { |example| travel_to(Time.zone.parse("2026-10-28 10:00")) { example.run } }

  describe "lista" do
    before { sign_in admin }

    it "mostra os KPIs, os status com o motivo traduzido e as ações por status" do
      create(:whatsapp_template, account: account, name: "proposta_enviada", status: "approved", meta_template_id: "1")
      create(:whatsapp_template, account: account, name: "cobranca_vencida", status: "pending", meta_template_id: "2")
      create(:whatsapp_template, account: account, name: "oferta_manutencao", status: "rejected", meta_template_id: "3",
                                 rejection_reason: "INCORRECT_CATEGORY — O texto é promocional.")
      create(:whatsapp_template, account: account, name: "pesquisa_satisfacao", status: "paused", meta_template_id: "4", category: "marketing")
      create(:whatsapp_template, account: account, name: "codigo_acesso", status: "approved", meta_template_id: "5", category: "authentication")
      create(:whatsapp_template, account: account, name: "antigo", status: "deleted", meta_template_id: "6")

      get whatsapp_templates_path

      body = response.body
      expect(body).to include("Sincronizar com a Meta", "Novo template", "disponíveis no envio",
                              "oferta_manutencao · categoria incorreta para o conteúdo (INCORRECT_CATEGORY). O texto é promocional.",
                              "aguardando a Meta", "Corrigir", "A 1ª pausa dura 3 h", "Utilidade", "Português (BR)",
                              "o nome só pode ser usado de novo depois de 30 dias")
      expect(body).not_to include("antigo")
      expect(body).to include(%(href="#{whatsapp_template_path(account.templates.find_by!(name: 'codigo_acesso'))}">Ver</a>))
      expect(body[/<aside class="side".*?<\/aside>/m]).to include(%(href="#{whatsapp_templates_path}"))
    end

    it "filtra por status, busca no nome e no corpo e troca de conta" do
      create(:whatsapp_template, account: account, name: "lembrete_reuniao", status: "approved",
                                 components: [ { "type" => "BODY", "text" => "Lembrete da reunião às {{1}}." } ])
      create(:whatsapp_template, account: account, name: "oferta", status: "rejected")
      other = create(:whatsapp_account, status: "connected", verified_name: "Cliente ACME", display_phone_number: "+55 11 3456-7890")
      create(:whatsapp_template, account: other, name: "boas_vindas_acme")

      get whatsapp_templates_path(status: "rejected")
      expect(response.body).to include("oferta").and(exclude("lembrete_reuniao"))

      get whatsapp_templates_path(q: "reuniao")
      expect(response.body).to include("lembrete_reuniao").and(exclude(">oferta</a>")) # o KPI de rejeitados segue mostrando a conta inteira

      expect(response.body).to include("Cliente ACME · +55 11 3456-7890")
      get whatsapp_templates_path(conta: other.id)
      expect(response.body).to include("boas_vindas_acme").and(exclude("lembrete_reuniao"))
    end

    it "explica por que a conta com o token vencido não sincroniza nem cria" do
      account.update!(status: "reconnect_required")
      get whatsapp_templates_path
      expect(response.body).to include("O acesso à Meta venceu").and(exclude("Novo template"))

      post sync_whatsapp_templates_path(conta: account.id)
      expect(flash[:alert]).to include("O acesso à Meta venceu")
      expect(WhatsappTemplateSyncJob).not_to have_been_enqueued
    end

    it "sincroniza pelo botão e mostra o andamento e a falha" do
      expect { post sync_whatsapp_templates_path(conta: account.id) }.to have_enqueued_job(WhatsappTemplateSyncJob).with(account)
      expect(account.reload.templates_sync_requested_at).to eq(Time.current)
      get whatsapp_templates_path
      expect(response.body).to include("Sincronizando com a Meta", "data-refresh-busy")

      account.update!(templates_sync_error: "O acesso ao WhatsApp expirou ou foi revogado. Conecte o número de novo.")
      get whatsapp_templates_path
      expect(response.body).to include("A sincronização falhou.", "expirou ou foi revogado")
    end
  end

  describe "criação" do
    before { sign_in admin }

    it "envia para análise com a categoria em maiúsculas e grava a categoria que a Meta devolveu" do
      requests = stub_graph(graph_response(200, { "id" => "594425", "status" => "PENDING", "category" => "MARKETING" }))

      post whatsapp_templates_path, params: { template: form }

      template = account.templates.find_by!(name: "lembrete_proposta")
      expect(response).to redirect_to(whatsapp_templates_path(conta: account.id))
      expect(flash[:notice]).to eq("lembrete_proposta enviado para análise da Meta. A Meta classificou como Marketing.")
      expect(template).to have_attributes(meta_template_id: "594425", status: "pending", category: "marketing", variables_count: 2)
      sent = json_body(requests.first)
      expect(sent).to include("name" => "lembrete_proposta", "language" => "pt_BR", "category" => "UTILITY")
      expect(sent["components"]).to eq(template.components)
      expect(sent["components"].last["buttons"].first).to include("type" => "URL", "example" => [ "https://admin.devbatista.com/p/P-2026-029" ])
      expect(AuditLog.where(auditable: template).pluck(:action)).to eq([ "create" ])
    end

    it "envia o exemplo da mídia do cabeçalho antes de criar" do
      requests = stub_graph(graph_response(200, { "id" => "upload:abc?sig=xyz" }), graph_response(200, { "h" => "4::handle" }),
                            graph_response(200, { "id" => "594426", "status" => "PENDING", "category" => "UTILITY" }))
      file = Rack::Test::UploadedFile.new(StringIO.new("%PDF-1.7"), "application/pdf", original_filename: "proposta.pdf")

      post whatsapp_templates_path, params: { template: form.merge(header_type: "document", header_file: file) }

      expect(response).to redirect_to(whatsapp_templates_path(conta: account.id))
      expect(requests.map { |r| r.path.split("?").first }).to eq([ "/v26.0/app-de-teste/uploads", "/v26.0/upload:abc", "/v26.0/#{account.waba_id}/message_templates" ])
      expect(account.templates.sole.component("HEADER")).to eq("type" => "HEADER", "format" => "DOCUMENT", "example" => { "header_handle" => [ "4::handle" ] })
    end

    it "recusa o formulário inválido sem chamar a Meta, mantendo o que foi digitado" do
      stub_graph
      post whatsapp_templates_path, params: { template: form.merge(body: "{{1}}, a proposta {{3}} vence amanhã.") }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("O corpo não pode começar nem terminar com uma variável", "sem pular números", "lembrete_proposta")
      expect(WhatsappTemplate.count).to eq(0)
    end

    it "recusa nome e idioma que já existem na conta" do
      create(:whatsapp_template, account: account, name: "lembrete_proposta", language: "pt_BR")
      stub_graph
      post whatsapp_templates_path, params: { template: form }
      expect(response.body).to include("Já existe o template lembrete_proposta em pt_BR nesta conta.")
    end

    it "mostra o erro da Meta em português" do
      stub_graph(graph_error(400, 368, "Temporarily blocked for policies violations"))
      post whatsapp_templates_path, params: { template: form }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("A conta do WhatsApp Business está bloqueada temporariamente por violação de política da Meta.")
      expect(WhatsappTemplate.count).to eq(0)
    end

    it "abre o editor com a prévia e o nome conferido no navegador" do
      get new_whatsapp_template_path
      expect(response.body).to include('data-controller="template-editor"', 'pattern="[a-z0-9_]{1,512}"', "Prévia", "como o contato vê",
                                       "+ Adicionar variável", "Marketing", "Utilidade")
      expect(response.body).not_to include("Autenticação")
    end
  end

  describe "edição" do
    before { sign_in admin }

    let!(:template) do
      create(:whatsapp_template, account: account, name: "lembrete_proposta", status: "approved", category: "utility", meta_template_id: "594425",
                                 components: Whatsapp::TemplateBuilder.new(form.except(:account_id)).components)
    end

    it "edita um aprovado sem mudar nome, idioma nem categoria, avisando que volta para análise" do
      get edit_whatsapp_template_path(template)
      expect(response.body).to include("Este template está aprovado.", "volta para a análise da Meta", "Novo site", "readonly")

      requests = stub_graph(graph_response(200, { "success" => true }))
      patch whatsapp_template_path(template), params: { template: form.merge(name: "outro_nome", category: "marketing", body: "Olá, {{1}}. A proposta {{2}} vence hoje.") }

      expect(response).to redirect_to(whatsapp_templates_path(conta: account.id))
      expect(requests.first.path).to eq("/v26.0/594425")
      expect(json_body(requests.first)).not_to have_key("category")
      expect(json_body(requests.first)["components"].find { |c| c["type"] == "BODY" }["text"]).to eq("Olá, {{1}}. A proposta {{2}} vence hoje.")
      expect(template.reload).to have_attributes(name: "lembrete_proposta", category: "utility", status: "pending", body_text: "Olá, {{1}}. A proposta {{2}} vence hoje.")
      expect(AuditLog.where(auditable: template).pluck(:action)).to contain_exactly("create", "status_change")
    end

    it "corrige um rejeitado mostrando o motivo, e pode trocar a categoria" do
      template.update!(status: "rejected", rejection_reason: "INCORRECT_CATEGORY")
      get edit_whatsapp_template_path(template)
      expect(response.body).to include("Rejeitado pela Meta:", "categoria incorreta para o conteúdo (INCORRECT_CATEGORY)")

      requests = stub_graph(graph_response(200, { "success" => true }))
      patch whatsapp_template_path(template), params: { template: form.merge(category: "marketing") }

      expect(json_body(requests.first)["category"]).to eq("MARKETING")
      expect(template.reload).to have_attributes(category: "marketing", status: "pending", rejection_reason: nil)
    end

    it "não edita um template em análise" do
      template.update!(status: "pending")
      stub_graph
      get edit_whatsapp_template_path(template)
      expect(response).to redirect_to(whatsapp_templates_path(conta: account.id))
      patch whatsapp_template_path(template), params: { template: form }
      expect(flash[:alert]).to include("Só templates aprovados, rejeitados ou pausados")
      expect(template.reload.status).to eq("pending")
    end

    it "mostra o limite de edição da Meta em português" do
      stub_graph(graph_error(400, 100, "Edit limit reached", details: "Você atingiu o limite de edições deste template."))
      patch whatsapp_template_path(template), params: { template: form }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Você atingiu o limite de edições deste template.")
      expect(template.reload.status).to eq("approved")
    end
  end

  describe "exclusão" do
    let!(:template) { create(:whatsapp_template, account: account, name: "lembrete_proposta", status: "approved", meta_template_id: "594425") }

    before { sign_in admin }

    it "exclui só aquele idioma na Meta e marca como excluído, sem apagar" do
      get edit_whatsapp_template_path(template)
      expect(response.body).to include("o nome só pode ser usado de novo depois de 30 dias")

      requests = stub_graph(graph_response(200, { "success" => true }))
      delete whatsapp_template_path(template)

      expect(requests.first.method).to eq("DELETE")
      expect(requests.first.path).to eq("/v26.0/#{account.waba_id}/message_templates?name=lembrete_proposta&hsm_id=594425")
      expect(template.reload).to be_status_deleted
      expect(flash[:notice]).to include("só pode ser usado de novo depois de 30 dias")
      expect(build(:whatsapp_template, account: account, name: "lembrete_proposta", language: template.language)).to be_valid
    end

    it "espera o envio em andamento com o template" do
      conversation = create(:whatsapp_conversation, account: account)
      create(:whatsapp_message, :outbound, conversation: conversation, kind: "template", status: "pending",
                                           template_name: "lembrete_proposta", template_language: template.language)
      stub_graph
      delete whatsapp_template_path(template)
      expect(flash[:alert]).to include("Há envio em andamento")
      expect(template.reload).to be_status_approved
    end
  end

  describe "permissões" do
    let!(:template) { create(:whatsapp_template, account: account, name: "lembrete_proposta", status: "approved", meta_template_id: "594425") }

    it "deixa quem só lê ver a lista e a prévia, sem criar, editar, excluir nem sincronizar" do
      sign_in reader
      get whatsapp_templates_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("lembrete_proposta").and(exclude("Novo template", "Sincronizar com a Meta", ">Editar<"))

      get whatsapp_template_path(template)
      expect(response.body).to include("Prévia", "como o contato vê").and(exclude(">Excluir<", ">Editar<"))

      stub_graph
      post whatsapp_templates_path, params: { template: form }
      expect(response).to have_http_status(:forbidden)
      patch whatsapp_template_path(template), params: { template: form }
      expect(response).to have_http_status(:forbidden)
      delete whatsapp_template_path(template)
      expect(response).to have_http_status(:forbidden)
      post sync_whatsapp_templates_path(conta: account.id)
      expect(response).to have_http_status(:forbidden)
    end

    it "barra quem não tem a área" do
      sign_in create(:user, :comercial)
      get whatsapp_templates_path
      expect(response).to have_http_status(:forbidden)
    end
  end
end
