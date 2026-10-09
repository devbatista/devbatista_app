# E-mail da proposta para o cliente (RF 10), com o PDF anexado e o link "Ver proposta",
# que marca Visualizada ao abrir. Layout próprio: o cliente não vê "Admin" nem "Não responda",
# e a resposta vai para o responsável.
class ProposalMailer < ApplicationMailer
  layout "client_mailer"
  helper :application

  def client(proposal:, document:, sender:, to:, subject:, message:, cc: [], bcc: [])
    @proposal = proposal
    @sender = sender
    @message = message
    @view_url = proposal_view_url(proposal.generate_token_for(:client_view))
    attachments[document.file.filename.to_s] = { mime_type: "application/pdf", content: document.file.download }

    mail(to: to, cc: cc, bcc: bcc, subject: subject,
         reply_to: (email_address_with_name(sender.email, sender.name) if sender.email.present?))
  end
end
