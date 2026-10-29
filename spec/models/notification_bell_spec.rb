require "rails_helper"
require "turbo/broadcastable/test_helper"

RSpec.describe "Sino de notificações em tempo real" do
  include Turbo::Broadcastable::TestHelper

  let(:user) { create(:user, :admin) }

  def bell_updates(&block)
    capture_turbo_stream_broadcasts([ user, :notifications ]) { perform_enqueued_jobs(only: Turbo::Streams::ActionBroadcastJob, &block) }
      .map { |stream| [ stream["action"], stream["target"] ] }
  end

  it "redesenha o contador e a lista quando um aviso é criado, atualizado ou lido" do
    notification = nil
    expect(bell_updates { notification = Notification.deliver!(kind: "ticket_critical", title: "Chamado crítico", users: [ user ]).sole })
      .to eq([ %w[replace notifications_bell_button], %w[replace notifications_bell_list] ])

    streams = capture_turbo_stream_broadcasts([ user, :notifications ]) do
      perform_enqueued_jobs(only: Turbo::Streams::ActionBroadcastJob) { notification.update!(title: "Chamado crítico #2") }
    end
    expect(streams.last.to_html).to include("Chamado crítico #2", "data-turbo-method=\"patch\"")

    expect(bell_updates { notification.update!(read_at: Time.current) }).to include(%w[replace notifications_bell_button])
  end

  it "redesenha também na marcação em lote", type: :request do
    Notification.deliver!(kind: "ticket_critical", title: "Chamado crítico", users: [ user ])
    sign_in user
    expect(bell_updates { patch read_all_notifications_path }).to include(%w[replace notifications_bell_button])
    expect(user.notifications.unread).to be_empty
  end

  it "o e-mail das mensagens do WhatsApp começa desligado nas preferências; os outros, ligados" do
    expect(user.email_for?("whatsapp_message")).to be(false)
    expect(user.email_for?("whatsapp_token_expiring")).to be(true)
    expect(Notification.receives?("whatsapp_message", create(:user, role: create(:role, permissions: { "whatsapp" => "read" })))).to be(true)
    expect(Notification.receives?("whatsapp_message", create(:user, :comercial))).to be(false)
  end
end
