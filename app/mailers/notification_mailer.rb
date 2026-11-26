# E-mail do alerta (RF 5): título e link para o sistema. O aviso de lead do site (site_lead) tem
# template próprio, com os dados do lead e do envio (params[:site_lead], montado pelo SiteLeadCapture).
class NotificationMailer < ApplicationMailer
  def alert(notification)
    @notification = notification
    @url = notification.path.present? ? "#{root_url.chomp('/')}#{notification.path}" : root_url
    @lead = notification.notifiable if notification.kind == "site_lead" && notification.notifiable.is_a?(Lead)
    @submission = params.fetch(:site_lead, {}).stringify_keys if @lead

    mail(to: notification.user.email, subject: "[Admin DevBatista] #{notification.title}", template_name: @lead ? "site_lead" : "alert")
  end
end
