# Pré-visualização em /rails/mailers (desenvolvimento).
class ProposalMailerPreview < ActionMailer::Preview
  # Arquivo em memória no lugar do Documento salvo: o preview não grava nada.
  PreviewFile = Struct.new(:filename, :content) do
    def download = content
  end

  def client
    proposal = Proposal.joins(:items).order(created_at: :desc).first
    pdf = ProposalPdf.new(proposal)
    document = Struct.new(:file).new(PreviewFile.new(ActiveStorage::Filename.new(pdf.filename), pdf.render))
    delivery = ProposalDelivery.new(proposal: proposal, user: proposal.user)
    ProposalMailer.client(proposal: proposal, document: document, sender: proposal.user, to: [ delivery.to || "cliente@exemplo.com.br" ],
                          subject: delivery.subject, message: delivery.message)
  end
end
