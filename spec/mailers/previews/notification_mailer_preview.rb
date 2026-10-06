# Pré-visualização em /rails/mailers (desenvolvimento).
class NotificationMailerPreview < ActionMailer::Preview
  def alert_critical
    NotificationMailer.alert(notification(kind: "receivable_overdue", level: "crit",
                                          title: "Título de R$ 4.800,00 da Acme vencido desde 03/10"))
  end

  def alert_warning
    NotificationMailer.alert(notification(kind: "contract_expiring", level: "warn",
                                          title: "Contrato #104 da Acme vence em 30 dias"))
  end

  def alert_info
    NotificationMailer.alert(notification(kind: "task_late", level: "info", title: "Tarefa “Ajustar checkout” passou do prazo"))
  end

  private

  def notification(**attributes)
    Notification.new(user: User.first, path: "/", **attributes)
  end
end
