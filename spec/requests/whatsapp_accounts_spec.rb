require "rails_helper"

RSpec.describe "Integrações → WhatsApp" do
  let(:admin) { create(:user, :admin, name: "Rafael Batista") }
  let(:token) { "EAAG-token-de-acesso-secreto" }
  let(:code) { "AQB-code-do-embedded-signup" }
  let(:waba_id) { "102938475610001" }
  let(:session_info) { { phone_number_id: "665544332211001", waba_id: waba_id, business_id: "106724254821671", is_on_biz_app: true } }
  let(:log) { StringIO.new }

  around { |example| travel_to(Time.zone.parse("2026-10-27 10:00")) { example.run } }

  before do
    logger = ActiveSupport::Logger.new(log)
    Rails.logger.broadcast_to(logger)
    @log_target = logger
  end

  after { Rails.logger.stop_broadcasting_to(@log_target) }

  def exchange
    graph_response(200, { "access_token" => token, "token_type" => "bearer" })
  end

  def debug_token(expires_at: 60.days.from_now.to_i, targets: [ waba_id ], app_id: "app-de-teste", valid: true)
    scopes = %w[whatsapp_business_management whatsapp_business_messaging].map { |scope| { "scope" => scope, "target_ids" => targets } }
    graph_response(200, { "data" => { "app_id" => app_id, "type" => "SYSTEM_USER", "is_valid" => valid, "expires_at" => expires_at, "granular_scopes" => scopes } })
  end

  def connect(**body)
    post connect_whatsapp_accounts_path, params: body.to_json, headers: { "Content-Type" => "application/json", "Accept" => "application/json" }
  end

  describe "conexão pelo Embedded Signup" do
    before { sign_in admin }

    it "troca o code, lê a validade no debug_token, salva a conta e enfileira a ativação" do
      requests = stub_graph(exchange, debug_token)

      expect { connect(code: code, **session_info) }.to have_enqueued_job(WhatsappActivationJob)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("url" => whatsapp_accounts_path)
      account = WhatsappAccount.find_by!(phone_number_id: "665544332211001")
      expect(account).to have_attributes(waba_id: waba_id, business_id: "106724254821671", coexistence: true, status: "pending",
                                         connected_by: admin, connected_at: Time.current, access_token: token,
                                         token_expires_at: 60.days.from_now, display_phone_number: nil)
      expect(requests.map(&:path)).to eq([ "/v26.0/oauth/access_token?client_id=app-de-teste&client_secret=segredo-de-teste&code=#{code}",
                                           "/v26.0/debug_token?input_token=#{token}&access_token=app-de-teste%7Csegredo-de-teste" ])
      expect(requests.map { |request| request["Authorization"] }).to all(be_nil)

      # O job leva só a referência da conta; o code, o token e o PIN não vão para o log nem para o inspect.
      expect(enqueued_jobs.last[:args]).to eq([ { "_aj_globalid" => account.to_global_id.to_s } ])
      expect(log.string).to include("[Whatsapp] número conectado", "[FILTERED]")
      expect(log.string).not_to include(code, token)
      expect(account.inspect).not_to include(token)
    end

    it "sem o session info, descobre a WABA no debug_token e o número em /<WABA>/phone_numbers" do
      number = { "id" => "665544332211009", "display_phone_number" => "+55 11 97070-2026", "verified_name" => "DevBatista" }
      requests = stub_graph(exchange, debug_token(expires_at: 0), graph_response(200, { "data" => [ number ] }))

      connect(code: code)

      expect(response).to have_http_status(:ok)
      expect(requests.last.path).to start_with("/v26.0/#{waba_id}/phone_numbers?fields=")
      expect(requests.last["Authorization"]).to eq("Bearer #{token}")
      account = WhatsappAccount.find_by!(phone_number_id: "665544332211009")
      expect(account).to have_attributes(waba_id: waba_id, display_phone_number: "+55 11 97070-2026", verified_name: "DevBatista",
                                         coexistence: false, token_expires_at: nil)
    end

    context "com o número já no Admin" do
      let(:synced) do
        { phone_number_id: "665544332211001", waba_id: waba_id, subscribed_at: 30.days.ago, contacts_sync_request_id: "req-antigo",
          contacts_synced_at: 30.days.ago, history_sync_request_id: "req-antigo-2", history_sync_progress: 100, history_synced_at: 30.days.ago }
      end

      def details
        graph_response(200, { "display_phone_number" => "+55 11 97070-2026", "verified_name" => "DevBatista", "quality_rating" => "GREEN",
                              "is_on_biz_app" => true, "platform_type" => "CLOUD_API" })
      end

      def paths(requests)
        requests.map { |request| request.path.split("?").first }
      end

      it "reconecta depois de uma desconexão no mesmo registro, mantendo as conversas e pedindo as sincronizações de novo" do
        account = create(:whatsapp_account, **synced, status: "disconnected", disconnected_at: 1.day.ago,
                                                      disconnect_reason: "PARTNER_REMOVED: ACCOUNT_DISCONNECTED", activation_error: "erro antigo")
        conversation = create(:whatsapp_conversation, account: account)
        stub_graph(exchange, debug_token)

        expect { connect(code: code, **session_info) }.not_to change(WhatsappAccount, :count)

        expect(account.reload).to have_attributes(status: "pending", disconnected_at: nil, disconnect_reason: nil, activation_error: nil,
                                                  subscribed_at: nil, contacts_sync_request_id: nil, contacts_synced_at: nil,
                                                  history_sync_request_id: nil, history_sync_progress: nil, history_synced_at: nil,
                                                  history_sync_error: nil, access_token: token)
        expect(conversation.reload.account).to eq(account)

        sync = ->(id) { graph_response(200, { "request_id" => id }) }
        requests = stub_graph(graph_response(200, { "success" => true }), details, sync.("req-novo"), sync.("req-novo-2"))
        perform_enqueued_jobs
        expect(paths(requests).count("/v26.0/665544332211001/smb_app_data")).to eq(2)
        expect(account.reload).to have_attributes(status: "connected", contacts_sync_request_id: "req-novo", history_sync_request_id: "req-novo-2")
      end

      it "renova o token de uma conta conectada mantendo as sincronizações, sem pedir de novo" do
        account = create(:whatsapp_account, **synced, status: "connected", token_expires_at: 3.days.from_now)
        requests = stub_graph(exchange, debug_token, details)

        perform_enqueued_jobs { connect(code: code, **session_info) }

        expect(paths(requests)).not_to include(a_string_matching(/smb_app_data|subscribed_apps/))
        expect(account.reload).to have_attributes(status: "connected", access_token: token, token_expires_at: 60.days.from_now,
                                                  contacts_sync_request_id: "req-antigo", contacts_synced_at: 30.days.ago,
                                                  history_sync_request_id: "req-antigo-2", history_sync_progress: 100,
                                                  history_synced_at: 30.days.ago, subscribed_at: 30.days.ago, activation_error: nil)
      end

      it "renova o token de uma conta que pedia reconexão, também sem pedir as sincronizações" do
        account = create(:whatsapp_account, **synced, status: "reconnect_required", token_expires_at: 1.day.ago)
        requests = stub_graph(exchange, debug_token, details)

        perform_enqueued_jobs { connect(code: code, **session_info) }

        expect(paths(requests)).not_to include(a_string_matching(/smb_app_data/))
        expect(account.reload).to have_attributes(status: "connected", history_synced_at: 30.days.ago)
      end
    end

    it "recusa o session info com WABA que não está entre as liberadas no token" do
      stub_graph(exchange, debug_token(targets: [ "999999999999999" ]))

      expect { connect(code: code, **session_info) }.not_to have_enqueued_job

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to eq("Não foi possível conectar: A conta informada pela janela da Meta não corresponde à autorização. Conecte de novo.")
      expect(WhatsappAccount.count).to eq(0)
      expect(log.string).to include("WABA do session info (#{waba_id}) fora dos target_ids do token (999999999999999)")
    end

    it "aceita o session info quando o debug_token não traz target_ids" do
      stub_graph(exchange, debug_token(targets: []))
      connect(code: code, **session_info)
      expect(response).to have_http_status(:ok)
      expect(WhatsappAccount.find_by!(phone_number_id: "665544332211001").waba_id).to eq(waba_id)
    end

    it "mostra o erro da Meta em português, sem salvar conta" do
      stub_graph(graph_error(400, 100, "Invalid verification code format.", details: "O code expirou"))

      expect { connect(code: code, **session_info) }.not_to have_enqueued_job

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to eq("Não foi possível conectar: O code expirou")
      expect(WhatsappAccount.count).to eq(0)
    end

    it "recusa token de outro app ou inválido" do
      stub_graph(exchange, debug_token(app_id: "outro-app"))
      connect(code: code, **session_info)
      expect(response.parsed_body["error"]).to include("outro app da Meta")

      stub_graph(exchange, debug_token(valid: false))
      connect(code: code, **session_info)
      expect(response.parsed_body["error"]).to include("não é válido")
      expect(WhatsappAccount.count).to eq(0)
    end

    it "sem o code, não chama a Meta" do
      stub_graph
      connect(**session_info)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to include("não devolveu a autorização")
    end

    it "registra no log só o passo e o código do cancelamento, descartando o que não for um identificador" do
      post signup_event_whatsapp_accounts_path, params: { current_step: "PHONE_NUMBER_VERIFICATION", error_code: "2388001", session_id: "f34b51dab5e0498" }.to_json,
                                                headers: { "Content-Type" => "application/json" }

      expect(response).to have_http_status(:no_content)
      expect(log.string).to include("Embedded Signup cancelado: passo=PHONE_NUMBER_VERIFICATION erro=2388001 session_id=f34b51dab5e0498")

      post signup_event_whatsapp_accounts_path, params: { current_step: "<script>" }.to_json, headers: { "Content-Type" => "application/json" }
      expect(log.string).to include("Embedded Signup cancelado: passo=-\n")
    end
  end

  describe "variáveis faltando" do
    before do
      sign_in admin
      allow(Whatsapp.config).to receive(:embedded_signup_config_id).and_return(nil)
    end

    it "avisa na tela, desabilita o botão e recusa a conexão" do
      get whatsapp_accounts_path
      expect(response.body).to include("Conexão desabilitada", "WHATSAPP_EMBEDDED_SIGNUP_CONFIG_ID")
      expect(response.body).to match(/data-open="whatsapp-connect" disabled/)
      expect(response.body).to include('data-whatsapp-signup-config-id-value=""')

      stub_graph
      connect(code: code, **session_info)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to include("WHATSAPP_EMBEDDED_SIGNUP_CONFIG_ID")
    end

    it "avisa quando faltam as chaves de criptografia do token" do
      allow(ActiveRecordEncryptionCheck).to receive(:missing_keys).and_return(%i[primary_key])
      get whatsapp_accounts_path
      expect(response.body).to include("ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY", "Faltam chaves")
    end
  end

  describe "acesso" do
    it "barra quem não é administrador" do
      sign_in create(:user, :comercial)
      get whatsapp_accounts_path
      expect(response).to have_http_status(:forbidden)

      stub_graph
      connect(code: code, **session_info)
      expect(response).to have_http_status(:forbidden)

      account = create(:whatsapp_account, status: "registration_pending", coexistence: false)
      post register_whatsapp_account_path(account), params: { pin: "123456" }
      expect(response).to have_http_status(:forbidden)
      expect(WhatsappAccount.count).to eq(1)
    end

    it "deixa quem só lê a área ver a tela, sem conectar" do
      sign_in create(:user, role: create(:role, permissions: { "whatsapp" => "read" }))
      get whatsapp_accounts_path
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Conectar WhatsApp")

      connect(code: code, **session_info)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "tela" do
    before { sign_in admin }

    it "mostra o número, a linha do tempo, os detalhes e os cartões do app e do webhook" do
      account = create(:whatsapp_account, status: "connected", connected_by: admin, connected_at: 2.hours.ago, subscribed_at: 2.hours.ago,
                                          contacts_sync_request_id: "r1", contacts_synced_at: 1.hour.ago, history_sync_request_id: "r2",
                                          history_sync_progress: 55, quality_rating: "green", messaging_limit_tier: "TIER_250",
                                          last_webhook_at: 2.minutes.ago, token_expires_at: 60.days.from_now)
      get whatsapp_accounts_path

      body = response.body
      expect(body).to include("DevBatista", "+55 11 97070-2026", "Conectado", "Coexistência", "Autorizado na Meta", "App inscrito na conta",
                              "Contatos sincronizados", "Histórico sincronizado", "55%", "Alta", "250 contatos novos em 24h", "20 mensagens/s",
                              account.waba_id, account.phone_number_id, "Rafael Batista", "Como desconectar",
                              "Configurações → Conta → Plataforma comercial", "app-de-teste", "Configurado · v5",
                              "http://www.example.com/webhooks/whatsapp", "phone_number_name_update", "há 2 minutos")
      expect(body).to include("data-refresh-busy") # o histórico ainda está sincronizando
      expect(body).not_to include("segredo-de-teste", "verificacao-de-teste", "token-de-acesso-de-teste")
      expect(body).to include("aparelhos conectados", "WhatsApp para Windows não é compatível", "só de leitura", "visualização única",
                              "deixe o app aberto no celular")
    end

    it "avisa da validade do token a partir de 7 dias do fim e pede reconexão depois de vencido" do
      account = create(:whatsapp_account, status: "connected", token_expires_at: 5.days.from_now)
      get whatsapp_accounts_path
      expect(response.body).to include("O acesso à Meta vence em 01/11/2026 10:00", "Reconectar")

      account.update!(token_expires_at: 8.days.from_now)
      get whatsapp_accounts_path
      expect(response.body).not_to include("O acesso à Meta vence")

      account.update!(status: "reconnect_required", token_expires_at: 1.day.ago)
      get whatsapp_accounts_path
      expect(response.body).to include("Reconectar necessário", "O acesso à Meta venceu em 26/10/2026 10:00")
    end

    it "mostra a falha da ativação com Tentar de novo, que retoma o job" do
      account = create(:whatsapp_account, status: "pending", activation_error: "O acesso ao WhatsApp expirou ou foi revogado. Conecte o número de novo.")
      get whatsapp_accounts_path
      expect(response.body).to include("A ativação parou", "expirou ou foi revogado", "Tentar de novo")
      expect(response.body).not_to include("data-refresh-busy")

      expect { post activate_whatsapp_account_path(account) }.to have_enqueued_job(WhatsappActivationJob).with(account)
      expect(response).to redirect_to(whatsapp_accounts_path)
      expect(account.reload.activation_error).to be_nil
    end
  end

  describe "registro do número sem coexistência" do
    let!(:account) { create(:whatsapp_account, status: "registration_pending", coexistence: false) }

    before { sign_in admin }

    it "pede o PIN na tela, registra na Cloud API e retoma a ativação, sem guardar o PIN" do
      get whatsapp_accounts_path
      expect(response.body).to include("Falta registrar o número", "PIN de 6 dígitos", "Aguardando registro")

      requests = stub_graph(graph_response(200, { "success" => true }))
      expect { post register_whatsapp_account_path(account), params: { pin: "246810" } }.to have_enqueued_job(WhatsappActivationJob).with(account)

      expect(response).to redirect_to(whatsapp_accounts_path)
      expect(json_body(requests.first)).to eq("messaging_product" => "whatsapp", "pin" => "246810")
      expect(account.reload).to have_attributes(status: "pending", registered_at: Time.current)
      expect(log.string).not_to include("246810")
    end

    it "mostra o erro da Meta e recusa PIN fora do formato" do
      post register_whatsapp_account_path(account), params: { pin: "12ab" }
      expect(flash[:alert]).to eq("O PIN tem 6 dígitos.")

      stub_graph(graph_error(400, 133_005, "Two step verification PIN Mismatch"))
      post register_whatsapp_account_path(account), params: { pin: "111111" }
      expect(flash[:alert]).to eq("Não foi possível registrar: O PIN da verificação em duas etapas não confere.")
      expect(account.reload).to be_registration_pending
    end
  end

  it "não envia COOP nem CSP que restrinja origens, que bloqueariam a janela da Meta" do
    sign_in admin
    get whatsapp_accounts_path
    expect(response.headers.keys.map(&:downcase)).not_to include("cross-origin-opener-policy")
    # Só o upgrade-insecure-requests (config/initializers/content_security_policy.rb), sem diretivas *-src.
    directives = response.headers["Content-Security-Policy"].to_s.split(";").map(&:strip).compact_blank
    expect(directives).to all(eq("upgrade-insecure-requests"))
  end
end
