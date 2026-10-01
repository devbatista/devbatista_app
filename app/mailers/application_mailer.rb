class ApplicationMailer < ActionMailer::Base
  default from: -> { "#{Setting[:company_name]} <#{Setting[:mailer_sender]}>" }
  layout "mailer"
end
