# Link "Ver proposta" do e-mail ao cliente (RF 10): abre o último PDF enviado, sem login.
# A primeira abertura pelo cliente passa a proposta de Enviada a Visualizada.
# Herda de ActionController::Base: fica fora do login e do bloqueio de navegadores antigos,
# já que o cliente pode abrir pelo navegador embutido do app de e-mail.
class ProposalViewsController < ActionController::Base
  def show
    proposal = Proposal.find_by_token_for(:client_view, params[:token])
    document = proposal&.sent_document
    return render(file: Rails.public_path.join("404.html"), status: :not_found, layout: false) unless document

    proposal.update!(status: "viewed") if proposal.sent? && !internal_user?
    send_data document.file.download, type: "application/pdf", disposition: "inline", filename: document.file.filename.to_s
  end

  private

  # Quem tem sessão no Admin (o responsável abrindo a cópia do e-mail) não conta como cliente.
  # Lê a sessão direto, sem passar pelo Devise, para não redirecionar ao login se ela expirou.
  def internal_user?
    session["warden.user.user.key"].present?
  end
end
