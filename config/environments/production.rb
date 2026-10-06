require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :amazon

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  # Somente HTTPS, com HSTS (requisito não funcional).
  config.force_ssl = true

  # Skip http-to-https redirect for the default health check endpoint.
  # config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  config.cache_store = :redis_cache_store, { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1") }

  # Replace the default in-process and non-durable queuing backend for Active Job.
  # config.active_job.queue_adapter = :resque

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Set host to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = { host: ENV.fetch("APP_HOST", "admin.devbatista.com"), protocol: "https" }
  # Imagens dos e-mails (logo) com URL absoluta.
  config.action_mailer.asset_host = "https://#{ENV.fetch("APP_HOST", "admin.devbatista.com")}"

  # Entrega via Amazon SES (interface SMTP). Aceita as credenciais SMTP geradas no console do SES
  # (`credentials` em `aws.ses` ou SES_SMTP_*) ou a chave IAM com permissão ses:SendRawEmail
  # (SES_ACCESS_KEY_ID e SES_SECRET_ACCESS_KEY): o usuário SMTP é o ID da chave e a senha é
  # derivada da chave secreta pelo algoritmo publicado pela AWS.
  # Erros de entrega levantam exceção para o Sidekiq tentar de novo.
  ses = Rails.application.credentials.dig(:aws, :ses) || {}
  ses_region = ses[:region] || ENV.fetch("SES_REGION", ENV.fetch("AWS_REGION", "sa-east-1"))
  ses_smtp_password = lambda do |secret|
    signature = [ "11111111", ses_region, "ses", "aws4_request", "SendRawEmail" ]
      .inject("AWS4#{secret}") { |key, data| OpenSSL::HMAC.digest("SHA256", key, data) }
    Base64.strict_encode64("\x04".b + signature)
  end
  config.action_mailer.delivery_method = :smtp
  config.action_mailer.raise_delivery_errors = true
  config.action_mailer.smtp_settings = {
    address: "email-smtp.#{ses_region}.amazonaws.com",
    # 2587 em vez de 587: o Railway bloqueia as portas SMTP padrão; o SES aceita STARTTLS nas duas.
    port: ENV.fetch("SES_SMTP_PORT", 2587).to_i,
    user_name: ses[:smtp_username] || ENV["SES_SMTP_USERNAME"] || ENV["SES_ACCESS_KEY_ID"],
    password: ses[:smtp_password] || ENV["SES_SMTP_PASSWORD"] ||
      (ses_smtp_password.call(ENV["SES_SECRET_ACCESS_KEY"]) if ENV["SES_SECRET_ACCESS_KEY"].present?),
    authentication: :login,
    enable_starttls_auto: true
  }

  # Specify outgoing SMTP server. Remember to add smtp/* credentials via bin/rails credentials:edit.
  # config.action_mailer.smtp_settings = {
  #   user_name: Rails.application.credentials.dig(:smtp, :user_name),
  #   password: Rails.application.credentials.dig(:smtp, :password),
  #   address: "smtp.example.com",
  #   port: 587,
  #   authentication: :plain
  # }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Enable DNS rebinding protection and other `Host` header attacks.
  # config.hosts = [
  #   "example.com",     # Allow requests from example.com
  #   /.*\.example\.com/ # Allow requests from subdomains like `www.example.com`
  # ]
  #
  # Skip DNS rebinding protection for the default health check endpoint.
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
