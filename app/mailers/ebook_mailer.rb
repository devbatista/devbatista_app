# E-book do site (docs/specs/leads-do-site): o link do PDF para quem pediu na landing page. Assunto,
# texto e HTML copiados do site (ebook_email_text e ebook_email_html em api/ebook.php), sem o layout
# do Admin. Sai do endereço pessoal do Rafael e sem Reply-To: o material é assinado por ele e
# responder o e-mail já cai na caixa certa.
class EbookMailer < ApplicationMailer
  SUBJECT = "Seu e-book chegou: onde a TI drena o lucro da sua empresa".freeze

  layout false

  # A URL vem de quem enfileira (SiteLeadCapture), que já conferiu que ela existe.
  def download(to:, url:)
    @url = url
    config = Rails.configuration.x.ebook
    mail(to: to, subject: SUBJECT, from: email_address_with_name(config.email_from, config.email_from_name))
  end
end
