class ApplicationMailer < ActionMailer::Base
  # proc, não lambda: o Devise avalia o remetente com instance_eval, que passa um argumento.
  default from: proc { "#{Setting[:company_name]} <#{Setting[:mailer_sender]}>" }
  layout "mailer"
  helper :mailer
end
