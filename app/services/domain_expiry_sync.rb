# Confere no RDAP o vencimento dos domínios (rotina diária, antes dos alertas de domínio).
# Se o registro diz que vence depois do que está no Admin, a renovação aconteceu (renovação
# automática na GoDaddy, boleto pago no Registro.br...) e é registrada com o novo vencimento.
# Vencimento anterior ao do Admin não é aplicado: fica só no log, para conferir à mão.
class DomainExpirySync
  def initialize(today = Date.current, lookup: Rdap.method(:expiration))
    @today = today
    @lookup = lookup
  end

  # Devolve os domínios renovados.
  def run
    Domain.find_each.filter_map { |domain| check(domain) }
  end

  private

  def check(domain)
    expires_on = @lookup.call(domain.name)
    return unless expires_on

    domain.update_column(:rdap_checked_at, Time.current)
    if expires_on > domain.expires_on
      domain.renew!(expires_on: expires_on, notes: "Renovação detectada no RDAP em #{I18n.l(@today)}.")
      domain
    elsif expires_on < domain.expires_on
      Rails.logger.warn("[DomainExpirySync] #{domain.name}: RDAP diz #{expires_on}, Admin diz #{domain.expires_on}")
      nil
    end
  rescue ActiveRecord::ActiveRecordError => e
    Rails.logger.warn("[DomainExpirySync] #{domain.name}: #{e.message}")
    nil
  end
end
