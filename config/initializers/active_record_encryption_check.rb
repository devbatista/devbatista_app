# Em produção, avisa no boot se faltar alguma chave do Active Record Encryption (nem no ambiente,
# nem nas credentials). Sem elas, salvar o token de uma conta do WhatsApp falha no meio da
# conexão. O aviso vai para o log como erro e não derruba o boot, para não tirar o Admin do ar.
module ActiveRecordEncryptionCheck
  KEYS = %i[primary_key deterministic_key key_derivation_salt].freeze

  def self.missing_keys(config = ActiveRecord::Encryption.config)
    KEYS.select do |key|
      config.public_send(key).blank?
    rescue ActiveRecord::Encryption::Errors::Configuration
      true
    end
  end

  def self.warn_if_missing(logger: Rails.logger, config: ActiveRecord::Encryption.config)
    missing = missing_keys(config)
    return if missing.empty?

    names = missing.map { |key| "ACTIVE_RECORD_ENCRYPTION_#{key.upcase}" }
    logger.error(
      "[Active Record Encryption] Faltam #{names.to_sentence} (nem no ambiente, nem nas credentials). " \
      "Conectar um número do WhatsApp vai falhar ao salvar o token. Gere com bin/rails db:encryption:init, " \
      "configure no Railway e guarde uma cópia segura: sem as mesmas chaves, os tokens salvos ficam ilegíveis."
    )
  end
end

Rails.application.config.after_initialize { ActiveRecordEncryptionCheck.warn_if_missing } if Rails.env.production?
