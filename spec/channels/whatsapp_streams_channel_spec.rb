require "rails_helper"

RSpec.describe "Tempo real do WhatsApp" do
  describe ApplicationCable::Connection, type: :channel do
    def warden(user)
      instance_double(Warden::Proxy, user: user)
    end

    it "recusa a conexão sem login ou de usuário inativo" do
      expect { connect "/cable", env: { "warden" => warden(nil) } }.to have_rejected_connection
      expect { connect "/cable", env: { "warden" => warden(create(:user, :admin, :inactive)) } }.to have_rejected_connection
    end

    it "recusa sem exceção a sessão expirada (o Devise faz throw :warden)" do
      proxy = instance_double(Warden::Proxy)
      allow(proxy).to receive(:user) { throw :warden, scope: :user, message: :timeout }
      expect { connect "/cable", env: { "warden" => proxy } }.to have_rejected_connection
    end

    it "identifica o usuário pela sessão do Devise" do
      user = create(:user, :admin)
      connect "/cable", env: { "warden" => warden(user) }
      expect(connection.current_user).to eq(user)
    end
  end

  describe WhatsappStreamsChannel, type: :channel do
    let(:conversation) { create(:whatsapp_conversation) }
    let(:stream) { Turbo::StreamsChannel.signed_stream_name([ conversation, :whatsapp ]) }

    it "deixa o administrador assinar o stream da conversa" do
      stub_connection current_user: create(:user, :admin)
      subscribe(signed_stream_name: stream)
      expect(subscription).to be_confirmed
      expect(subscription).to have_stream_from(Turbo::StreamsChannel.verified_stream_name(stream))
    end

    it "recusa quem não pode ver a área, mesmo com o nome assinado" do
      stub_connection current_user: create(:user, :comercial)
      subscribe(signed_stream_name: stream)
      expect(subscription).to be_rejected
    end

    it "recusa nome de stream sem assinatura" do
      stub_connection current_user: create(:user, :admin)
      subscribe(signed_stream_name: "gid://devbatista/WhatsappConversation/#{conversation.id}:whatsapp")
      expect(subscription).to be_rejected
    end
  end

  describe NotificationsChannel, type: :channel do
    let(:user) { create(:user, :admin) }

    it "deixa assinar só o stream do próprio usuário" do
      stub_connection current_user: user
      subscribe(signed_stream_name: Turbo::StreamsChannel.signed_stream_name([ user, :notifications ]))
      expect(subscription).to be_confirmed
      expect(subscription).to have_stream_from("#{user.to_gid_param}:notifications")

      subscribe(signed_stream_name: Turbo::StreamsChannel.signed_stream_name([ create(:user, :admin), :notifications ]))
      expect(subscription).to be_rejected
    end
  end
end
