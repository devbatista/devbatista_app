require "rails_helper"

RSpec.describe WhatsappMediaJob do
  include ActiveJob::TestHelper

  let(:message) { create(:whatsapp_message, kind: "image", body: nil, media_id: "1003383421387256", media_mime_type: "image/jpeg") }
  let(:content) { "conteúdo-da-foto" }
  let(:info) { graph_response(200, { "url" => "https://lookaside.fbsbx.com/m", "mime_type" => "image/jpeg", "sha256" => Digest::SHA256.hexdigest(content), "id" => "1003383421387256" }) }

  it "baixa a mídia para o Active Storage com nome e tipo, e não baixa de novo" do
    stub_graph(info, graph_response(200, content))
    described_class.perform_now(message)

    expect(message.media).to be_attached
    expect(message.media.filename.to_s).to eq("whatsapp-1003383421387256.jpg")
    expect(message.media.content_type).to eq("image/jpeg")
    expect(message.media.download).to eq(content.b)

    expect { described_class.perform_now(message.reload) }.not_to raise_error # nenhuma chamada a mais à Graph API
  end

  it "usa o nome do documento" do
    message.update!(kind: "document", media_mime_type: "application/pdf", media_filename: "escopo.pdf")
    stub_graph(graph_response(200, { "url" => "https://lookaside.fbsbx.com/m", "mime_type" => "application/pdf", "id" => "1" }), graph_response(200, "%PDF"))
    described_class.perform_now(message)
    expect(message.media.filename.to_s).to eq("escopo.pdf")
  end

  it "desiste da falha definitiva, com aviso no log, e tenta de novo a transitória" do
    allow(Rails.logger).to receive(:warn)
    stub_graph(graph_error(400, 100, "(#100) Media expired"))
    expect { described_class.perform_now(message) }.not_to have_enqueued_job(described_class)
    expect(message.media).not_to be_attached
    expect(Rails.logger).to have_received(:warn).with(a_string_including("não baixada", "Media expired"))

    stub_graph(graph_error(503, 2, "Service temporarily unavailable"))
    expect { described_class.perform_now(message) }.to have_enqueued_job(described_class)
  end
end
