class ApplicationController < ActionController::Base
  include Pundit::Authorization
  include Listing

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :set_current_request
  before_action :authenticate_user!
  after_action :verify_authorized, unless: :devise_controller?

  layout -> { devise_controller? ? "auth" : "application" }

  # Permissão é checada no servidor: rota sem permissão responde 403.
  rescue_from Pundit::NotAuthorizedError, with: :forbidden

  private

  # Não chama current_user aqui, para não autenticar a sessão nas telas do Devise
  # (login e senha). O usuário entra no Current em authenticate_user!.
  def set_current_request
    Current.ip_address = request.remote_ip
  end

  def authenticate_user!
    super
    Current.user = current_user
  end

  def forbidden
    respond_to do |format|
      format.html { render "errors/forbidden", status: :forbidden }
      format.json { render json: { error: "Sem permissão" }, status: :forbidden }
      format.any { head :forbidden }
    end
  end

  def after_sign_in_path_for(_user)
    stored_location_for(:user) || root_path
  end

  def after_sign_out_path_for(_scope)
    new_user_session_path
  end
end
