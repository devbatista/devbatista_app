# Jobs em segundo plano. O sidekiq-cron carrega as rotinas de config/schedule.yml.
redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }

# Quando um job falha, o Sidekiq registra no log o job inteiro, com os argumentos. Os jobs que
# não registram argumentos (log_arguments = false, como o WhatsappWebhookJob, que recebe o
# payload com mensagens e telefones) saem do log com os argumentos omitidos.
module SidekiqPrivateArguments
  def self.filter(context)
    job = context[:job]
    return context unless job.is_a?(Hash) && private?(job)

    context.except(:jobstr).merge(job: job.merge("args" => "[FILTERED]"))
  end

  def self.private?(job)
    job_class = (job["wrapped"] || job["class"]).to_s.safe_constantize
    job_class.respond_to?(:log_arguments?) && !job_class.log_arguments?
  end

  def self.error_handler
    ->(exception, context, config = Sidekiq.default_configuration) { Sidekiq::Config::ERROR_HANDLER.call(exception, filter(context), config) }
  end
end

Sidekiq.configure_server do |config|
  config.redis = redis
  config.error_handlers.delete(Sidekiq::Config::ERROR_HANDLER)
  config.error_handlers << SidekiqPrivateArguments.error_handler
end
Sidekiq.configure_client { |config| config.redis = redis }
