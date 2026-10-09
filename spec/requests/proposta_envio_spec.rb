require "rails_helper"

RSpec.describe "Proposta em PDF e envio por e-mail" do
  let(:comercial) { create(:user, :comercial, email: "ana@devbatista.com") }
  let(:company) { create(:company) }
  let(:contact) { create(:contact, company: company, name: "Maria Souza", email: "maria@acme.com.br") }
  let(:opportunity) { create(:opportunity, company: company, stage: "meeting") }
  let(:proposal) { create(:proposal, company: company, contact: contact, opportunity: opportunity, user: comercial) }

  def deliver(target = proposal, **overrides)
    post deliver_proposal_path(target), params: { delivery: { to: "maria@acme.com.br", cc: "", subject: "Proposta", message: "Olá!",
                                                              copy_me: "1" }.merge(overrides) }
  end

  it "gera o PDF da proposta para conferir" do
    sign_in comercial
    get pdf_proposal_path(proposal)
    expect(response.media_type).to eq("application/pdf")
    expect(response.body).to start_with("%PDF")
    expect(response.headers["Content-Disposition"]).to include("inline", "proposta-P-")
  end

  it "sugere o contato da proposta como destinatário" do
    sign_in comercial
    get deliver_proposal_path(proposal)
    expect(response.body).to include("maria@acme.com.br", "Olá, Maria!", proposal.code)
  end

  it "envia o rascunho: Enviada, PDF em Documentos, interação na oportunidade e e-mail na fila" do
    sign_in comercial
    expect { deliver(proposal, cc: "joao@acme.com.br") }.to have_enqueued_mail(ProposalMailer, :client)

    proposal.reload
    expect(response).to redirect_to(proposal_path(proposal))
    expect(proposal).to be_sent
    expect(proposal.sent_at).to be_present
    expect(opportunity.reload).to be_stage_proposal
    document = proposal.sent_document
    expect(document.file.download).to start_with("%PDF")
    expect(document.uploaded_by).to eq(comercial)
    expect(document.company).to eq(company)
    expect(opportunity.interactions.last.notes).to include(proposal.code, "maria@acme.com.br", "joao@acme.com.br")
  end

  it "reenvia sem mudar o status e guarda as duas versões" do
    sign_in comercial
    deliver
    proposal.update!(status: "viewed")
    deliver
    expect(proposal.reload).to be_viewed
    expect(proposal.documents.count).to eq(2)
  end

  it "usa o e-mail do lead quando a proposta é para um lead" do
    lead = create(:lead, name: "Paulo Lima", email: "paulo@lima.com.br")
    lead_proposal = create(:proposal, company: nil, lead: lead, user: comercial)
    sign_in comercial
    get deliver_proposal_path(lead_proposal)
    expect(response.body).to include("paulo@lima.com.br", "Olá, Paulo!")

    deliver(lead_proposal, to: "paulo@lima.com.br")
    expect(lead_proposal.reload).to be_sent
    expect(lead.interactions.last).to be_email
  end

  it "não envia com e-mail inválido nem proposta já decidida" do
    sign_in comercial
    expect { deliver(proposal, to: "maria@", cc: "ok@acme.com.br") }.not_to have_enqueued_mail
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("E-mail inválido: maria@")
    expect(proposal.reload).to be_draft
    expect(proposal.documents).to be_empty

    proposal.update!(status: "rejected", rejection_reason: "Preço")
    expect { deliver }.not_to have_enqueued_mail
    expect(response.body).to include("Proposta recusada não pode ser enviada")
  end

  it "não envia proposta sem serviços" do
    proposal.items.destroy_all
    sign_in comercial
    expect { deliver }.not_to have_enqueued_mail
    expect(response.body).to include("Inclua ao menos um serviço antes de enviar")
  end

  it "deixa o financeiro ver o PDF, mas não enviar" do
    sign_in create(:user, :financeiro)
    get pdf_proposal_path(proposal)
    expect(response).to have_http_status(:ok)
    deliver
    expect(response).to have_http_status(:forbidden)
  end

  describe "link do e-mail (sem login)" do
    let(:token) { proposal.generate_token_for(:client_view) }

    before do
      sign_in comercial
      deliver
      sign_out comercial
    end

    it "abre o PDF enviado e marca a proposta como Visualizada" do
      get proposal_view_path(token)
      expect(response.media_type).to eq("application/pdf")
      expect(response.body).to start_with("%PDF")
      proposal.reload
      expect(proposal).to be_viewed
      expect(proposal.viewed_at).to be_present
      expect(AuditLog.where(auditable: proposal, action: "status_change").last.user).to be_nil
    end

    it "não conta a abertura de quem está logado no Admin" do
      sign_in comercial
      get proposal_view_path(token)
      expect(response).to have_http_status(:ok)
      expect(proposal.reload).to be_sent
    end

    it "responde 404 para link inválido ou proposta sem envio" do
      get proposal_view_path("token-invalido")
      expect(response).to have_http_status(:not_found)

      draft = create(:proposal, company: company)
      get proposal_view_path(draft.generate_token_for(:client_view))
      expect(response).to have_http_status(:not_found)
    end
  end
end
