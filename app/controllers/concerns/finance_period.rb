# Seletor de período das telas do Financeiro: um mês (padrão: o corrente), o trimestre ou o ano.
# Os meses vão de `back` meses atrás até `forward` meses à frente (títulos previstos).
module FinancePeriod
  extend ActiveSupport::Concern

  private

  def set_period(back: 6, forward: 3, extra: true)
    current = Date.current.beginning_of_month
    months = (-forward..back).map { |i| current << i }
    @periods = months.map { |m| [ "#{I18n.l(m, format: '%B/%Y').capitalize}#{' (previstas)' if m > current}", m.strftime("%Y-%m") ] }
    @periods += [ [ "Trimestre atual", "trimestre" ], [ "Ano de #{current.year}", "ano" ] ] if extra
    @period = params[:periodo].presence_in(@periods.map(&:last)) || current.strftime("%Y-%m")
    @range =
      case @period
      when "trimestre" then Date.current.all_quarter
      when "ano" then Date.current.all_year
      else Date.strptime(@period, "%Y-%m").all_month
      end
    @period_label = @periods.to_h.invert[@period].to_s.sub(" (previstas)", "")
  end
end
