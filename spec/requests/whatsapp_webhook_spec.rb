require "rails_helper"

RSpec.describe "Webhook do WhatsApp" do
  include ActiveJob::TestHelper

  let(:body) do
    JSON.generate(
      object: "whatsapp_business_account",
      entry: [ { id: "1029384756102938", time: 1_761_570_000,
                 changes: [ { field: "messages", value: { messaging_product: "whatsapp", messages: [ { id: "wamid.1" } ] } },
                            { field: "smb_message_echoes", value: { messaging_product: "whatsapp" } } ] } ]
    )
  end

  def signature(payload, secret = "segredo-de-teste")
    "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", secret, payload)}"
  end

  def post_webhook(payload, signature_header)
    post "/webhooks/whatsapp", params: payload, headers: { "Content-Type" => "application/json", "X-Hub-Signature-256" => signature_header }.compact
  end

  describe "verificação" do
    it "devolve o challenge quando o token confere, sem login" do
      get "/webhooks/whatsapp", params: { "hub.mode" => "subscribe", "hub.verify_token" => "verificacao-de-teste", "hub.challenge" => "1158201444" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("1158201444")
    end

    it "recusa token errado, modo errado e token não configurado" do
      get "/webhooks/whatsapp", params: { "hub.mode" => "subscribe", "hub.verify_token" => "outro", "hub.challenge" => "1" }
      expect(response).to have_http_status(:forbidden)
      get "/webhooks/whatsapp", params: { "hub.mode" => "unsubscribe", "hub.verify_token" => "verificacao-de-teste", "hub.challenge" => "1" }
      expect(response).to have_http_status(:forbidden)

      allow(Whatsapp.config).to receive(:webhook_verify_token).and_return(nil)
      get "/webhooks/whatsapp", params: { "hub.mode" => "subscribe", "hub.verify_token" => "", "hub.challenge" => "1" }
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "eventos" do
    it "aceita o corpo assinado e enfileira um job por mudança, sem processar na requisição" do
      expect { post_webhook(body, signature(body)) }.to have_enqueued_job(WhatsappWebhookJob).exactly(2).times
      expect(response).to have_http_status(:ok)
      expect(WhatsappWebhookJob).to have_been_enqueued.with("1029384756102938", "messages", hash_including("messages" => [ { "id" => "wamid.1" } ]), 1_761_570_000)
      expect(WhatsappWebhookJob).to have_been_enqueued.with("1029384756102938", "smb_message_echoes", anything, 1_761_570_000)
    end

    it "recusa assinatura errada, ausente, de outro segredo ou de outro corpo" do
      [ "sha256=#{'0' * 64}", nil, signature(body, "outro-segredo"), signature("#{body} ") ].each do |header|
        expect { post_webhook(body, header) }.not_to have_enqueued_job
        expect(response).to have_http_status(:unauthorized)
      end
    end

    it "recusa tudo sem o app secret configurado, com erro no log" do
      allow(Whatsapp.config).to receive(:app_secret).and_return(nil)
      allow(Rails.logger).to receive(:error)
      expect { post_webhook(body, signature(body, "")) }.not_to have_enqueued_job
      expect(response).to have_http_status(:unauthorized)
      expect(Rails.logger).to have_received(:error).with(/META_APP_SECRET/)
    end

    it "ignora outro objeto e responde 400 a JSON inválido assinado" do
      other = JSON.generate(object: "page", entry: [ { id: "1", changes: [ { field: "feed", value: {} } ] } ])
      expect { post_webhook(other, signature(other)) }.not_to have_enqueued_job
      expect(response).to have_http_status(:ok)

      post_webhook("{nao-e-json", signature("{nao-e-json"))
      expect(response).to have_http_status(:bad_request)
    end

    it "não leva o conteúdo das mensagens para o log da requisição" do
      filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
      filtered = filter.filter(JSON.parse(body).merge("time_entry" => { "minutes" => 30 }))
      expect(filtered["entry"]).to eq("[FILTERED]")
      expect(filtered["time_entry"]).to eq("minutes" => 30)
    end
  end
end
