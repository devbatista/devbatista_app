require "rails_helper"

RSpec.describe WhatsappWebhookJob do
  include ActiveJob::TestHelper

  let(:account) { create(:whatsapp_account) }
  let(:value) do
    { messaging_product: "whatsapp", metadata: { phone_number_id: account.phone_number_id },
      contacts: [ wa_contact(name: "Henrique Duarte") ], messages: [ wa_message("wamid.LOG1", "Fechamos em R$ 12.000?") ] }.deep_stringify_keys
  end
  let(:log) { StringIO.new }

  around do |example|
    original = ActiveJob::Base.logger
    ActiveJob::Base.logger = ActiveSupport::Logger.new(log)
    example.run
  ensure
    ActiveJob::Base.logger = original
  end

  it "não leva o conteúdo da mensagem, o nome nem o telefone para o log ao enfileirar e ao executar" do
    described_class.perform_later(account.waba_id, "messages", value)
    described_class.perform_now(account.waba_id, "messages", value)

    expect(log.string).to include("Enqueued WhatsappWebhookJob", "Performed WhatsappWebhookJob")
    expect(log.string).not_to include("R$ 12.000", "Henrique", WhatsappWebhookHelpers::CONTACT_PHONE, WhatsappWebhookHelpers::CONTACT_BSUID)
    expect(WhatsappMessage.find_by(wa_message_id: "wamid.LOG1")).to be_present
  end

  it "deixa o job da mídia registrar só a referência da mensagem (GlobalID)" do
    message = create(:whatsapp_message, body: "Segue o comprovante", media_id: "1003383421387256", media_mime_type: "image/jpeg")
    WhatsappMediaJob.perform_later(message)

    expect(log.string).to include("gid://", "WhatsappMessage/#{message.id}")
    expect(log.string).not_to include("Segue o comprovante", message.conversation.wa_id)
  end
end
