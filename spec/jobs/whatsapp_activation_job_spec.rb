require "rails_helper"

RSpec.describe WhatsappActivationJob do
  let(:account) { create(:whatsapp_account, status: "pending", coexistence: true, display_phone_number: nil, verified_name: nil, connected_at: Time.current) }

  def subscribed
    graph_response(200, { "success" => true })
  end

  def details(coexistence: true, platform: "CLOUD_API")
    graph_response(200, { "display_phone_number" => "+55 11 97070-2026", "verified_name" => "DevBatista", "quality_rating" => "GREEN",
                          "whatsapp_business_manager_messaging_limit" => "TIER_250", "is_on_biz_app" => coexistence,
                          "platform_type" => platform, "id" => account.phone_number_id })
  end

  def sync(id)
    graph_response(200, { "messaging_product" => "whatsapp", "request_id" => id })
  end

  def paths(requests)
    requests.map { |request| "#{request.method} #{request.path.split('?').first}" }
  end

  it "com coexistência: inscreve o app, lê o número, pede contatos e depois histórico, e conecta, sem register" do
    requests = stub_graph(subscribed, details, sync("req-contatos"), sync("req-historico"))

    described_class.perform_now(account)

    expect(paths(requests)).to eq([ "POST /v26.0/#{account.waba_id}/subscribed_apps", "GET /v26.0/#{account.phone_number_id}",
                                    "POST /v26.0/#{account.phone_number_id}/smb_app_data", "POST /v26.0/#{account.phone_number_id}/smb_app_data" ])
    expect(requests.last(2).map { |request| json_body(request)["sync_type"] }).to eq(%w[smb_app_state_sync history])
    expect(account.reload).to have_attributes(status: "connected", subscribed_at: be_present, display_phone_number: "+55 11 97070-2026",
                                              verified_name: "DevBatista", quality_rating: "green", messaging_limit_tier: "TIER_250",
                                              contacts_sync_request_id: "req-contatos", history_sync_request_id: "req-historico",
                                              activation_error: nil)
  end

  it "é idempotente: rodar de novo não inscreve nem pede as sincronizações outra vez" do
    stub_graph(subscribed, details, sync("req-contatos"), sync("req-historico"))
    described_class.perform_now(account)
    expect(described_class.perform_now(account.reload)).to be_nil # conectado: nada a fazer

    account.update!(status: "pending")
    requests = stub_graph(details) # uma chamada a mais falharia o teste
    described_class.perform_now(account)
    expect(paths(requests)).to eq([ "GET /v26.0/#{account.phone_number_id}" ])
    expect(account.reload).to have_attributes(status: "connected", contacts_sync_request_id: "req-contatos", history_sync_request_id: "req-historico")
  end

  it "sem coexistência, não sincroniza e fica aguardando o registro; depois do PIN, conecta" do
    account.update!(coexistence: false)
    requests = stub_graph(subscribed, details(coexistence: false, platform: "NOT_APPLICABLE"))

    described_class.perform_now(account)

    expect(paths(requests)).not_to include(a_string_matching(/smb_app_data|register/))
    expect(account.reload).to have_attributes(status: "registration_pending", coexistence: false, contacts_sync_request_id: nil)

    account.update!(status: "pending", registered_at: Time.current) # o que a tela faz depois do register(pin:)
    requests = stub_graph(details(coexistence: false, platform: "NOT_APPLICABLE"))
    described_class.perform_now(account)
    expect(paths(requests)).to eq([ "GET /v26.0/#{account.phone_number_id}" ])
    expect(account.reload).to be_connected
  end

  it "sem coexistência e já registrado na Cloud API, conecta sem pedir o PIN" do
    account.update!(coexistence: false)
    stub_graph(subscribed, details(coexistence: false, platform: "CLOUD_API"))
    described_class.perform_now(account)
    expect(account.reload).to be_connected
  end

  it "reconhece a coexistência pelo is_on_biz_app quando a conexão veio sem session info" do
    account.update!(coexistence: false)
    stub_graph(subscribed, details(coexistence: true), sync("req-contatos"), sync("req-historico"))
    described_class.perform_now(account)
    expect(account.reload).to have_attributes(coexistence: true, status: "connected", history_sync_request_id: "req-historico")
  end

  it "não tenta de novo a sincronização repetida (2593107) nem a fora do prazo (2593108), e explica o caminho" do
    stub_graph(subscribed, details, graph_error(400, 2_593_107, "Sync already requested"), sync("req-historico"))

    expect { described_class.perform_now(account) }.not_to have_enqueued_job(described_class)
    expect(account.reload).to have_attributes(status: "connected", contacts_sync_request_id: "already-requested", history_sync_request_id: "req-historico")
    expect(account.activation_error).to eq("A sincronização com o app do celular já foi feita para este número. " \
                                           "Para sincronizar, desconecte no celular e conecte o número de novo.")

    account.update!(status: "pending")
    stub_graph(details) # o marcador evita pedir os contatos de novo
    described_class.perform_now(account)
    expect(account.reload).to be_connected

    other = create(:whatsapp_account, status: "pending", coexistence: true)
    stub_graph(subscribed, details, graph_error(400, 2_593_108, "Sync window expired"), graph_error(400, 2_593_108, "Sync window expired"))
    expect { described_class.perform_now(other) }.not_to have_enqueued_job(described_class)
    expect(other.reload.activation_error).to start_with("O prazo de 24h para sincronizar com o app do celular acabou.")
    expect(other).to be_connected
  end

  it "trata o 2593107 como sincronização já pedida, sem aviso, quando o histórico já chegou" do
    account.update!(history_synced_at: 2.days.ago, history_sync_progress: 100)
    stub_graph(subscribed, details, graph_error(400, 2_593_107, "Sync already requested"), graph_error(400, 2_593_107, "Sync already requested"))

    described_class.perform_now(account)

    expect(account.reload).to have_attributes(status: "connected", activation_error: nil, contacts_sync_request_id: "already-requested",
                                              history_sync_request_id: "already-requested")
  end

  it "não sobrescreve a desconexão que chega pelo webhook durante a ativação" do
    response = details
    body = response.body
    allow(response).to receive(:body) do
      WhatsappAccount.where(id: account.id).update_all(status: "disconnected", disconnect_reason: "PARTNER_REMOVED: ACCOUNT_DISCONNECTED")
      body
    end
    stub_graph(subscribed, response) # sem smb_app_data: a conta desconectada não pede as sincronizações

    described_class.perform_now(account)

    expect(account.reload).to have_attributes(status: "disconnected", disconnect_reason: "PARTNER_REMOVED: ACCOUNT_DISCONNECTED",
                                              contacts_sync_request_id: nil, verified_name: "DevBatista")
  end

  it "também não passa para Aguardando registro se a conta foi desconectada" do
    account.update!(coexistence: false)
    response = details(coexistence: false, platform: "NOT_APPLICABLE")
    body = response.body
    allow(response).to receive(:body) do
      WhatsappAccount.where(id: account.id).update_all(status: "disconnected")
      body
    end
    stub_graph(subscribed, response)
    described_class.perform_now(account)
    expect(account.reload).to be_disconnected
  end

  it "tenta de novo a falha transitória e grava a definitiva em português, sem retry" do
    stub_graph(graph_error(503, 2, "Service temporarily unavailable"))
    expect { described_class.perform_now(account) }.to have_enqueued_job(described_class).with(account)
    expect(account.reload).to have_attributes(status: "pending", activation_error: nil)

    stub_graph(graph_error(401, 190, "Error validating access token"))
    expect { described_class.perform_now(account) }.not_to have_enqueued_job(described_class)
    expect(account.reload).to have_attributes(status: "pending", activation_error: "O acesso ao WhatsApp expirou ou foi revogado. Conecte o número de novo.")
  end

  it "grava a falha quando as tentativas da transitória acabam" do
    stub_graph(*Array.new(5) { graph_error(503, 2, "Service temporarily unavailable") })
    perform_enqueued_jobs { described_class.perform_later(account) }
    expect(account.reload.activation_error).to eq("Service temporarily unavailable")
  end

  it "retoma da etapa que falhou" do
    stub_graph(subscribed, details, sync("req-contatos"), graph_error(400, 100, "(#100) Invalid parameter", details: "Parâmetro inválido"))
    described_class.perform_now(account)
    expect(account.reload).to have_attributes(status: "pending", subscribed_at: be_present, contacts_sync_request_id: "req-contatos",
                                              history_sync_request_id: nil, activation_error: "Parâmetro inválido")

    requests = stub_graph(details, sync("req-historico"))
    described_class.perform_now(account)
    expect(paths(requests)).to eq([ "GET /v26.0/#{account.phone_number_id}", "POST /v26.0/#{account.phone_number_id}/smb_app_data" ])
    expect(json_body(requests.last)["sync_type"]).to eq("history")
    expect(account.reload).to have_attributes(status: "connected", history_sync_request_id: "req-historico", activation_error: nil)
  end

  it "não leva o token nem a conta para o log do Active Job" do
    log = StringIO.new
    original = ActiveJob::Base.logger
    ActiveJob::Base.logger = ActiveSupport::Logger.new(log)
    described_class.perform_later(account)
    expect(log.string).to include("Enqueued WhatsappActivationJob")
    expect(log.string).not_to include(account.access_token, "gid://")
  ensure
    ActiveJob::Base.logger = original
  end
end
