require "rails_helper"

RSpec.describe ActiveRecordEncryptionCheck do
  let(:logger) { instance_double(Logger, error: nil) }

  it "não avisa quando as três chaves existem" do
    expect(described_class.missing_keys).to be_empty
    described_class.warn_if_missing(logger: logger)
    expect(logger).not_to have_received(:error)
  end

  it "registra erro com as variáveis que faltam, sem levantar exceção" do
    config = ActiveRecord::Encryption::Config.new
    config.primary_key = "chave-primaria"
    expect(described_class.missing_keys(config)).to eq(%i[deterministic_key key_derivation_salt])

    described_class.warn_if_missing(logger: logger, config: config)
    expect(logger).to have_received(:error).with(
      a_string_including("ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY e ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT", "Railway", "ilegíveis")
    )
  end
end
