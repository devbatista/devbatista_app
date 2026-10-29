require "rails_helper"
require "turbo/broadcastable/test_helper"

RSpec.describe Whatsapp::Notifier do
  include Turbo::Broadcastable::TestHelper

  let!(:admin) { create(:user, :admin, name: "Rafael Batista") }
  let!(:reader) { create(:user, role: create(:role, permissions: { "whatsapp" => "read" })) }
  let!(:outsider) { create(:user, :comercial) }
  let(:account) { create(:whatsapp_account, status: "connected") }
  let(:at) { Time.zone.parse("2026-10-27 10:00") }

  around { |example| travel_to(Time.zone.parse("2026-10-27 10:30")) { example.run } }

  def receive(id, body, minutes: 0, **extra)
    process_webhook(account, "messages", contacts: [ wa_contact(name: "Henrique Duarte") ], messages: [ wa_message(id, body, at: at + minutes.minutes, **extra) ])
  end

  def conversation = account.conversations.sole

  it "cria o aviso da conversa para quem vê a área, com o nome, a prévia e o link da conversa" do
    receive("wamid.N1", "Consegue terça?")

    notifications = Notification.where(kind: "whatsapp_message")
    expect(notifications.map(&:user)).to contain_exactly(admin, reader)
    expect(notifications.first).to have_attributes(title: "Henrique Duarte · 1 mensagem nova", body: "Consegue terça?", notifiable: conversation,
                                                   path: "/whatsapp/conversations/#{conversation.id}", area: "whatsapp", level: "info", read_at: nil)
  end

  it "a mensagem seguinte atualiza o mesmo aviso, que sobe na lista; depois de lido, a próxima cria outro" do
    receive("wamid.N1", "Consegue terça?")
    first = admin.notifications.sole
    Notification.deliver!(kind: "ticket_critical", title: "Chamado crítico", users: [ admin ]) # mais novo que o aviso, até a próxima mensagem

    travel 5.minutes
    receive("wamid.N2", "Às 10h?", minutes: 5)

    expect(admin.notifications.where(kind: "whatsapp_message").sole).to have_attributes(id: first.id, title: "Henrique Duarte · 2 mensagens novas", body: "Às 10h?")
    expect(first.reload.created_at).to eq(Time.current)
    expect(admin.notifications.recent.first).to eq(first)

    conversation.update!(unread_count: 0)
    expect(first.reload.read_at).to be_present
    expect(reader.notifications.unread).to be_empty

    receive("wamid.N3", "Alô?", minutes: 10)
    expect(admin.notifications.where(kind: "whatsapp_message").map(&:title)).to contain_exactly("Henrique Duarte · 2 mensagens novas", "Henrique Duarte · 1 mensagem nova")
  end

  it "histórico, reação, aviso do sistema e eco do celular não geram aviso" do
    receive("wamid.N1", "Oi")
    conversation.update!(unread_count: 0)
    Notification.delete_all

    receive("wamid.R1", nil, type: "reaction", reaction: { message_id: "wamid.N1", emoji: "👍" })
    process_webhook(account, "smb_message_echoes", message_echoes: [
      { from: WhatsappWebhookHelpers::BUSINESS_PHONE, to: "+#{WhatsappWebhookHelpers::CONTACT_PHONE}", id: "wamid.E1", timestamp: at.to_i.to_s, type: "text", text: { body: "Te ligo já" } }
    ])
    [ create(:whatsapp_message, conversation: conversation, from_history: true), create(:whatsapp_message, conversation: conversation, kind: "system", body: "Trocou de número") ]
      .each { |message| described_class.message_received(message) }

    expect(Notification.count).to eq(0)
  end

  it "o eco do celular (resposta pelo app) marca os avisos da conversa como lidos" do
    receive("wamid.N1", "Oi")
    process_webhook(account, "smb_message_echoes", message_echoes: [
      { from: WhatsappWebhookHelpers::BUSINESS_PHONE, to: "+#{WhatsappWebhookHelpers::CONTACT_PHONE}", id: "wamid.E1", timestamp: (at + 1.minute).to_i.to_s, type: "text", text: { body: "Te ligo já" } }
    ])
    expect(Notification.unread.where(kind: "whatsapp_message")).to be_empty
  end

  it "não avisa a mensagem cuja conversa alguém já abriu antes do aviso sair" do
    conversation = create(:whatsapp_conversation, account: account, unread_count: 0)
    described_class.message_received(create(:whatsapp_message, conversation: conversation))
    expect(Notification.count).to eq(0)
  end

  it "manda o e-mail só para quem ligou nas preferências (desligado por padrão), e só na criação do aviso" do
    Setting[:email_enabled] = true
    admin.update!(email_preferences: { "whatsapp_message" => true })
    expect(reader.email_for?("whatsapp_message")).to be(false)

    expect { receive("wamid.N1", "Oi") }.to have_enqueued_mail(NotificationMailer, :alert).once
    expect { receive("wamid.N2", "Tudo bem?", minutes: 1) }.not_to have_enqueued_mail(NotificationMailer, :alert)
  end

  it "manda ao navegador de cada um o nome, a prévia e o endereço, sem o conteúdo nos argumentos do job" do
    streams = capture_turbo_stream_broadcasts([ admin, :notifications ]) do
      perform_enqueued_jobs(only: Turbo::Streams::ActionBroadcastJob) { receive("wamid.N1", "Consegue terça?") }
    end

    alert = streams.find { |stream| stream["action"] == "append" && stream["target"] == "whatsapp_alerts" }
    html = alert.to_html
    expect(html).to include('data-whatsapp-alerts-target="alert"', 'data-title="Henrique Duarte"', 'data-body="Consegue terça?"',
                            %(data-conversation-id="#{conversation.id}"), %(data-message-id="#{conversation.messages.sole.id}"))

    receive("wamid.N2", "Meu CPF é 123", minutes: 1)
    args = enqueued_jobs.select { |job| job["job_class"] == "Turbo::Streams::ActionBroadcastJob" }.map { |job| job["arguments"].to_json }
    expect(args.join).not_to include("CPF", "Henrique")
  end
end
