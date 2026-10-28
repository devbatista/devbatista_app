require "rails_helper"
require "turbo/broadcastable/test_helper"

RSpec.describe "Broadcasts do WhatsApp" do
  include Turbo::Broadcastable::TestHelper

  let(:account) { create(:whatsapp_account, status: "connected") }

  def captured(*streamables, &block)
    capture_turbo_stream_broadcasts(streamables) { perform_enqueued_jobs(only: Turbo::Streams::ActionBroadcastJob, &block) }
  end

  it "mensagem recebida pelo webhook atualiza a conversa, a lista e o contador do menu" do
    process_webhook(account, "messages", contacts: [ wa_contact(name: "Henrique Duarte") ], messages: [ wa_message("wamid.B1", "Consegue terça?") ])
    conversation = account.conversations.sole
    clear_enqueued_jobs

    thread = inbox = nil
    menu = capture_turbo_stream_broadcasts(:whatsapp_menu) do
      inbox = capture_turbo_stream_broadcasts([ account, :whatsapp_inbox ]) do
        thread = captured(conversation, :whatsapp) do
          process_webhook(account, "messages", contacts: [ wa_contact(name: "Henrique Duarte") ],
                                               messages: [ wa_message("wamid.B2", "Às 10h?", at: Time.zone.parse("2026-10-27 10:10")) ])
        end
      end
    end

    message = conversation.messages.find_by!(wa_message_id: "wamid.B2")
    expect(thread.map { |s| [ s["action"], s["target"] ] }).to include([ "append", ActionView::RecordIdentifier.dom_id(conversation, :thread) ])
    expect(thread.find { |s| s["action"] == "append" }.to_html).to include(ActionView::RecordIdentifier.dom_id(message), "Às 10h?")
    expect(inbox.map { |s| s["action"] }).to eq(%w[remove prepend])
    expect(inbox.last.to_html).to include("Henrique Duarte", "Às 10h?", %(class="pill">2))
    expect(menu.sole.to_html).to include(%(id="whatsapp_menu_counter"), ">1<")
  end

  it "status da mensagem enviada substitui o balão" do
    conversation = create(:whatsapp_conversation, account: account, last_message_at: 1.hour.ago)
    sent = create(:whatsapp_message, :outbound, conversation: conversation, wa_message_id: "wamid.S1", status: "sent", body: "Confirmado")
    clear_enqueued_jobs

    thread = captured(conversation, :whatsapp) { process_webhook(account, "messages", statuses: [ wa_status("wamid.S1", "delivered") ]) }

    expect(thread.sole["action"]).to eq("replace")
    expect(thread.sole["target"]).to eq(ActionView::RecordIdentifier.dom_id(sent))
    expect(thread.sole.to_html).to include("Entregue")
  end

  it "reação redesenha a mensagem reagida, e não entra como mensagem nova" do
    conversation = create(:whatsapp_conversation, account: account, last_message_at: 1.hour.ago, wa_id: WhatsappWebhookHelpers::CONTACT_PHONE,
                                                  bsuid: WhatsappWebhookHelpers::CONTACT_BSUID)
    reacted = create(:whatsapp_message, :outbound, conversation: conversation, wa_message_id: "wamid.R1", body: "Proposta enviada")
    clear_enqueued_jobs

    thread = captured(conversation, :whatsapp) do
      process_webhook(account, "messages", contacts: [ wa_contact ], messages: [ wa_message("wamid.R2", type: "reaction", reaction: { message_id: "wamid.R1", emoji: "👍" }) ])
    end

    expect(thread.map { |s| s["target"] }.uniq).to eq([ ActionView::RecordIdentifier.dom_id(reacted) ])
    expect(thread.last.to_html).to include("👍")
  end

  it "janela que fecha no envio (131047) redesenha o cabeçalho e o campo de envio" do
    conversation = create(:whatsapp_conversation, account: account, last_message_at: 1.hour.ago, last_inbound_at: 1.hour.ago)
    thread = captured(conversation, :whatsapp) { conversation.update!(last_inbound_at: 25.hours.ago) }
    expect(thread.map { |s| s["target"] }).to eq([ ActionView::RecordIdentifier.dom_id(conversation, :header), ActionView::RecordIdentifier.dom_id(conversation, :composer) ])
    expect(thread.last.to_html).to include("Responder com template")
  end
end

RSpec.describe WhatsappReadJob do
  let(:conversation) { create(:whatsapp_conversation, account: create(:whatsapp_account, status: "connected"), last_message_at: 1.hour.ago) }

  it "marca como lida na Meta a última recebida, uma vez por mensagem" do
    create(:whatsapp_message, conversation: conversation, wa_message_id: "wamid.L1", sent_at: 10.minutes.ago)
    create(:whatsapp_message, conversation: conversation, wa_message_id: "wamid.L2", sent_at: 5.minutes.ago)
    requests = stub_graph(graph_response(200, { "success" => true }))

    described_class.perform_now(conversation)
    described_class.perform_now(conversation) # nada novo: não chama a Meta de novo

    expect(requests.size).to eq(1)
    expect(json_body(requests.first)).to include("status" => "read", "message_id" => "wamid.L2")
    expect(conversation.messages.inbound.pluck(:read_at)).to all(be_present)
  end

  it "não trava a conversa durante a chamada e registra só o código e o fbtrace_id da falha" do
    create(:whatsapp_message, conversation: conversation, wa_message_id: "wamid.L1", body: "Meu CPF é 123")
    expect(conversation).not_to receive(:with_lock)
    allow(Rails.logger).to receive(:warn)
    stub_graph(graph_error(400, 100, "Invalid parameter: wamid.L1 Meu CPF é 123"))

    described_class.perform_now(conversation)

    expect(Rails.logger).to have_received(:warn).with("[Whatsapp] leitura não marcada na conversa #{conversation.id}: code=100 fbtrace_id=AbCdEf123")
    expect(conversation.messages.inbound.sole.read_at).to be_nil
  end
end
