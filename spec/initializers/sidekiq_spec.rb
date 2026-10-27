require "rails_helper"

RSpec.describe SidekiqPrivateArguments do
  let(:log) { StringIO.new }
  # Mesmo formatter do servidor, que imprime o contexto (o job) em cada linha.
  let(:config) { Sidekiq::Config.new.tap { |c| c.logger = Sidekiq::Logger.new(log).tap { |l| l.formatter = Sidekiq::Logger::Formatters::Pretty.new } } }

  def job_hash(wrapped, args)
    { "class" => "Sidekiq::ActiveJob::Wrapper", "wrapped" => wrapped, "queue" => "default", "jid" => "b4a577edbccf1d805744efa9",
      "args" => [ { "job_class" => wrapped, "arguments" => args } ] }
  end

  it "tira do log de falha os argumentos dos jobs que não registram argumentos" do
    job = job_hash("WhatsappWebhookJob", [ "1029384756", "messages", { "messages" => [ { "from" => "5511991023344", "text" => { "body" => "Fechamos em R$ 12.000?" } } ] } ])
    described_class.error_handler.call(RuntimeError.new("falhou"), { context: "Job raised exception", job: job, jobstr: JSON.generate(job) }, config)

    expect(log.string).to include("falhou", "WhatsappWebhookJob", "b4a577edbccf1d805744efa9", "[FILTERED]")
    expect(log.string).not_to include("5511991023344", "R$ 12.000")
  end

  it "mantém os argumentos dos outros jobs e o contexto sem job" do
    job = job_hash("ProposalAlertsJob", [ "2026-10-27" ])
    expect(described_class.filter({ job: job })).to eq(job: job)
    expect(described_class.filter({ context: "Error calling retries_exhausted" })).to eq(context: "Error calling retries_exhausted")
  end

  it "substitui o handler padrão do Sidekiq no servidor" do
    handlers = Sidekiq.default_configuration.error_handlers
    original = handlers.dup
    allow(Sidekiq).to receive(:server?).and_return(true)
    load Rails.root.join("config/initializers/sidekiq.rb")

    expect(handlers).not_to include(Sidekiq::Config::ERROR_HANDLER)
    expect(handlers.size).to eq(original.size)
  ensure
    handlers.replace(original)
  end
end
