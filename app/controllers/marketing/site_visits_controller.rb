module Marketing
  # Visitas do site (docs/specs/visitas-do-site): os seis indicadores do período com a comparação ao
  # anterior e o gráfico de visitas. O cálculo é o SiteVisits::Stats, o mesmo das tools do MCP.
  # Cache de até 15 minutos, menos em Hoje e Ontem, que mudam a cada visita.
  class SiteVisitsController < ApplicationController
    LIVE_PERIODS = %w[hoje ontem].freeze

    def index
      authorize :site_visit, :index?
      @period = SiteVisits::Stats.period(params[:periodo])
      @periods = SiteVisits::Stats::PERIODS.invert.to_a
      @empty = !SiteVisit.exists?
      return if @empty

      stats = SiteVisits::Stats.new(@period)
      @summary =
        if LIVE_PERIODS.include?(@period.key) then stats.summary.merge(generated_at: Time.current)
        else Rails.cache.fetch([ "visitas-do-site", @period.key, Date.current ], expires_in: ::DashboardController::CACHE_TTL) { stats.summary.merge(generated_at: Time.current) }
        end
    end
  end
end
