require "rails_helper"

RSpec.describe WhatsappTemplateSyncJob do
  let(:account) { create(:whatsapp_account, status: "connected") }
  let(:body) { [ { "type" => "BODY", "text" => "Olá, {{1}}. Tudo bem?" } ] }

  around { |example| travel_to(Time.zone.parse("2026-10-28 07:00")) { example.run } }

  def meta(id, name, status: "APPROVED", category: "UTILITY", language: "pt_BR", reason: "NONE")
    { "id" => id, "name" => name, "language" => language, "category" => category, "status" => status,
      "components" => body, "parameter_format" => "POSITIONAL", "rejected_reason" => reason }
  end

  def page(*templates, after: nil)
    paging = after ? { "cursors" => { "after" => after }, "next" => "https://graph.facebook.com/next" } : { "cursors" => {} }
    graph_response(200, { "data" => templates, "paging" => paging })
  end

  it "grava pelo ID, por nome e idioma quando ainda sem ID, e traz os criados no Gerenciador, seguindo a paginação" do
    by_id = create(:whatsapp_template, account: account, meta_template_id: "111", name: "proposta_enviada", status: "pending")
    by_name = create(:whatsapp_template, account: account, meta_template_id: nil, name: "lembrete_reuniao", status: "pending")
    rejected = create(:whatsapp_template, account: account, meta_template_id: "333", name: "oferta", status: "rejected",
                                          category: "utility", rejection_reason: "INCORRECT_CATEGORY")
    requests = stub_graph(page(meta("111", "proposta_enviada"), meta("222", "lembrete_reuniao"), after: "CURSOR2"),
                          page(meta("333", "oferta", category: "MARKETING"), meta("444", "criado_no_gerenciador", language: "en_US", category: "MARKETING")))

    described_class.perform_now(account)

    expect(requests.size).to eq(2)
    expect(by_id.reload).to have_attributes(status: "approved", last_synced_at: Time.current)
    expect(by_name.reload).to have_attributes(meta_template_id: "222", status: "approved")
    expect(rejected.reload).to have_attributes(status: "approved", category: "marketing", rejection_reason: nil)
    created = account.templates.find_by!(meta_template_id: "444")
    expect(created).to have_attributes(name: "criado_no_gerenciador", language: "en_US", category: "marketing", status: "approved", variables_count: 1)
    expect(account.reload).to have_attributes(templates_synced_at: Time.current, templates_sync_error: nil)
  end

  it "marca como excluído o template que sumiu da Meta, sem apagar, e libera o nome" do
    gone = create(:whatsapp_template, account: account, meta_template_id: "555", name: "pesquisa_satisfacao", status: "approved")
    stub_graph(page(meta("666", "pesquisa_satisfacao")))

    described_class.perform_now(account)

    expect(gone.reload).to have_attributes(status: "deleted", last_synced_at: Time.current)
    expect(account.templates.find_by!(meta_template_id: "666")).to have_attributes(name: "pesquisa_satisfacao", status: "approved")
    expect(account.templates.count).to eq(2)
  end

  it "usa o padrão seguro para status e categoria desconhecidos e avisa do motivo de rejeição desconhecido" do
    allow(Rails.logger).to receive(:warn)
    stub_graph(page(meta("777", "novo_tipo", status: "EM_REVISAO_ESPECIAL", category: "NOVA_CATEGORIA"),
                    meta("888", "rejeitado", status: "REJECTED", reason: "MOTIVO_NOVO")))

    described_class.perform_now(account)

    expect(account.templates.find_by!(meta_template_id: "777")).to have_attributes(status: "pending", category: "utility")
    rejected = account.templates.find_by!(meta_template_id: "888")
    expect(rejected.rejection_label).to eq("MOTIVO_NOVO")
    expect(Rails.logger).to have_received(:warn).with("[Whatsapp] motivo de rejeição desconhecido: MOTIVO_NOVO, template=rejeitado")
  end

  it "não sincroniza conta desconectada nem com o token vencido" do
    stub_graph # uma chamada falharia o teste
    %w[disconnected reconnect_required].each do |status|
      account.update!(status: status)
      described_class.perform_now(account)
    end
    expect(account.reload.templates_synced_at).to be_nil
  end

  it "tenta de novo a falha transitória e grava a definitiva em português" do
    stub_graph(graph_error(503, 2, "Service temporarily unavailable"))
    expect { described_class.perform_now(account) }.to have_enqueued_job(described_class)
    expect(account.reload.templates_sync_error).to be_nil

    stub_graph(graph_error(401, 190, "Error validating access token"))
    expect { described_class.perform_now(account) }.not_to have_enqueued_job(described_class)
    expect(account.reload.templates_sync_error).to eq("O acesso ao WhatsApp expirou ou foi revogado. Conecte o número de novo.")
  end

  it "roda na rotina diária para as contas com acesso válido" do
    create(:whatsapp_account, status: "disconnected")
    create(:whatsapp_account, status: "reconnect_required")
    account

    expect { DailyAlertsJob.perform_now }.to have_enqueued_job(described_class).with(account).exactly(:once)
  end

  it "continua deixando o webhook de status atualizar o template certo depois da sincronização" do
    stub_graph(page(meta("1689556908129832", "order_confirmation", status: "PENDING", language: "en_US")))
    described_class.perform_now(account)

    process_change("message_template_status_update", { event: "APPROVED", message_template_id: 1_689_556_908_129_832, message_template_name: "order_confirmation",
                                                       message_template_language: "en-US", reason: "NONE", message_template_category: "UTILITY" },
                   entry_id: account.waba_id)

    expect(account.templates.sole).to have_attributes(meta_template_id: "1689556908129832", status: "approved")
  end
end
