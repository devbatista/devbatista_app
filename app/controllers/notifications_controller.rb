class NotificationsController < ApplicationController
  def index
    authorize Notification
    scope = policy_scope(Notification).recent
    @unread_count = scope.unread.count
    scope = scope.unread if params[:filtro] == "nao-lidas"
    scope = scope.where(area: params[:area]) if params[:area].present?
    @notifications, @pager = paginate(scope)
  end

  # Marca como lida e abre o registro.
  def update
    notification = authorize Notification.find(params[:id])
    notification.update!(read_at: Time.current) unless notification.read?
    redirect_to notification.path.presence || notifications_path
  end

  # Preferências de e-mail do próprio usuário, por tipo de alerta.
  def preferences
    authorize Notification, :index?
    chosen = Array(params[:email_kinds])
    current_user.update!(email_preferences: Notification::KINDS.keys.index_with { |kind| chosen.include?(kind) })
    redirect_to notifications_path, notice: "Preferências de e-mail salvas."
  end

  def read_all
    authorize Notification, :index?
    policy_scope(Notification).unread.update_all(read_at: Time.current)
    redirect_back fallback_location: notifications_path, notice: "Todas as notificações foram marcadas como lidas."
  end
end
