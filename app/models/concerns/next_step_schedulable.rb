# Próximo passo de lead e oportunidade (next_step + next_step_on), com data e hora em Brasília.
# É o que alimenta a lista Comercial → Próximos passos (NextStepList) e as tools do MCP.
#
# Só a data (Date ou "AAAA-MM-DD", como era antes de existir a hora) vale às 09:00, para não
# quebrar quem ainda manda só o dia.
module NextStepSchedulable
  extend ActiveSupport::Concern

  DEFAULT_HOUR = 9
  DATE_ONLY = /\A\d{4}-\d{2}-\d{2}\z/

  # Atalhos do "Adiar" na lista: chave do parâmetro → rótulo do botão.
  POSTPONE_OPTIONS = { "1h" => "+1 hora", "amanha" => "Amanhã, 9h", "segunda" => "Próxima segunda, 9h" }.freeze

  included do
    scope :with_next_step_date, -> { where.not(next_step_on: nil) }
    scope :next_step_overdue, ->(now = Time.current) { where(next_step_on: ...now) }
  end

  class << self
    # Valor recebido (tela, MCP ou código) → horário em Brasília, ou nil se vazio ou inválido.
    def cast(value)
      case value
      when nil then nil
      when ActiveSupport::TimeWithZone, Time, DateTime then value.in_time_zone
      when Date then at_default_hour(value)
      else parse(value.to_s.strip)
      end
    end

    # Data e hora de um atalho do "Adiar", a partir de agora.
    def postpone_time(option, now = Time.current)
      case option
      when "1h" then (now + 1.hour).change(sec: 0)
      when "amanha" then at_default_hour(now.to_date.tomorrow)
      when "segunda" then at_default_hour(now.to_date.next_occurring(:monday))
      end
    end

    private

    def parse(text)
      return nil if text.empty?
      return at_default_hour(Date.iso8601(text)) if text.match?(DATE_ONLY)

      Time.zone.iso8601(text.sub(" ", "T"))
    rescue ArgumentError, Date::Error
      nil
    end

    def at_default_hour(date)
      date.in_time_zone.change(hour: DEFAULT_HOUR)
    end
  end

  def next_step_on=(value)
    super(NextStepSchedulable.cast(value))
  end

  def next_step_overdue?(now = Time.current)
    next_step_on.present? && next_step_on < now
  end
end
