require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Devbatista
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # Interface em português, horários em Brasília.
    config.time_zone = "Brasilia"
    config.i18n.default_locale = :"pt-BR"
    config.i18n.available_locales = [ :"pt-BR" ]

    config.active_job.queue_adapter = :sidekiq

    # O schema em SQL preserva o trigger que torna a auditoria imutável.
    config.active_record.schema_format = :sql

    # Servidor MCP (/mcp): endereço público (identifica o recurso e o emissor no OAuth), hosts
    # aceitos além de localhost (proteção contra DNS rebinding) e token fixo de desenvolvimento,
    # que só existe fora de produção.
    config.x.mcp.base_url = "https://#{ENV.fetch("APP_HOST", "admin.devbatista.com")}"
    config.x.mcp.allowed_hosts = [ ENV.fetch("APP_HOST", "admin.devbatista.com") ]
    config.x.mcp.dev_token = nil

    config.generators do |g|
      # Chaves em UUID v4 (default gen_random_uuid() no banco; ver RegenerateIdsAsUuidV4).
      g.orm :active_record, primary_key_type: :uuid
      g.test_framework :rspec, fixture: false, view_specs: false, helper_specs: false, routing_specs: false
      g.factory_bot dir: "spec/factories"
      g.system_tests = nil
      g.helper false
      g.stylesheets false
    end
  end
end
