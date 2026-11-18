# Link público da fatura (docs/specs/faturas): /f/<token>, sem login e sem prazo. Mostra a fatura
# com o Pix e baixa o PDF. A primeira abertura por quem não está logado marca "visualizada".
# Herda de ActionController::Base, como o link da proposta: fica fora do login e do bloqueio de
# navegadores antigos, já que o cliente pode abrir pelo navegador embutido do app de e-mail.
class InvoiceViewsController < ActionController::Base
  layout "client"

  before_action :set_invoice

  def show
    @invoice.mark_viewed! if @invoice.issued? && !internal_user?
    @pix = PixPayload.new(amount_cents: @invoice.total_cents, txid: @invoice.txid) if @invoice.issued?
  end

  def pdf
    pdf = InvoicePdf.new(@invoice, view_url: invoice_view_url(params[:token]))
    send_data pdf.render, type: "application/pdf", disposition: "attachment", filename: pdf.filename
  end

  private

  # Rascunho não tem link: o token só é mostrado depois da emissão.
  def set_invoice
    @invoice = Invoice.includes(:company, :items).find_by_token_for(:client_view, params[:token])
    render(file: Rails.public_path.join("404.html"), status: :not_found, layout: false) if @invoice.nil? || @invoice.draft?
  end

  # Quem tem sessão no Admin (conferindo o link) não conta como cliente. Lê a sessão direto, sem
  # passar pelo Devise, para não redirecionar ao login se ela expirou.
  def internal_user?
    session["warden.user.user.key"].present?
  end
end
