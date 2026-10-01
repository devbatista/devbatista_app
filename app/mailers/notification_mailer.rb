class NotificationMailer < ApplicationMailer
  def alert(notification)
    @notification = notification
    @url = notification.path.present? ? "#{root_url.chomp('/')}#{notification.path}" : root_url
    mail(to: notification.user.email, subject: "[Admin DevBatista] #{notification.title}")
  end
end
