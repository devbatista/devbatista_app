# Sal do hash do visitante, um por dia (fuso do app). Aleatório e apagado no dia seguinte pelo
# SiteVisitSaltCleanupJob: sem ele, não há como refazer o hash e reconhecer o visitante de novo.
# Nunca derive o sal de algo fixo (secret_key_base, data): daria para testar todos os IPs.
class SiteVisitSalt < ApplicationRecord
  validates :day, :salt, presence: true

  def self.for(day = Date.current)
    find_by(day: day)&.salt || create_or_find_by!(day: day) { |record| record.salt = SecureRandom.hex(32) }.salt
  end
end
