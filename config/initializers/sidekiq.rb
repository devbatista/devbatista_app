# Jobs em segundo plano. O sidekiq-cron carrega as rotinas de config/schedule.yml.
redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }

Sidekiq.configure_server { |config| config.redis = redis }
Sidekiq.configure_client { |config| config.redis = redis }
