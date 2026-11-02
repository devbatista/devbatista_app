require "rails_helper"

RSpec.describe EscritorioStreamsChannel, type: :channel do
  let(:stream) { Turbo::StreamsChannel.signed_stream_name(:escritorio) }

  it "deixa o administrador assinar o stream do escritório" do
    stub_connection current_user: create(:user, :admin)
    subscribe(signed_stream_name: stream)
    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from("escritorio")
  end

  it "recusa quem não pode ver a área, mesmo com o nome assinado" do
    stub_connection current_user: create(:user, :comercial)
    subscribe(signed_stream_name: stream)
    expect(subscription).to be_rejected
  end

  it "recusa nome de stream sem assinatura" do
    stub_connection current_user: create(:user, :admin)
    subscribe(signed_stream_name: "escritorio")
    expect(subscription).to be_rejected
  end
end
