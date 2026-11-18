# E-mail da fatura para o cliente (docs/specs/faturas), com o PDF anexado e o botão "Ver fatura"
# (link público, com o Pix). Mesmo layout do e-mail da proposta: a resposta vai para quem enviou.
class InvoiceMailer < ApplicationMailer
  layout "client_mailer"
  helper :application

  def client(invoice:, document:, sender:, to:, subject:, message:, cc: [], bcc: [])
    @invoice = invoice
    @sender = sender
    @message = message
    @view_url = invoice_view_url(invoice.generate_token_for(:client_view))
    attachments[document.file.filename.to_s] = { mime_type: "application/pdf", content: document.file.download }

    mail(to: to, cc: cc, bcc: bcc, subject: subject,
         reply_to: (email_address_with_name(sender.email, sender.name) if sender.email.present?))
  end
end
