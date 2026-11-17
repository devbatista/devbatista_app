module Marketing
  # Visitas do site (docs/specs/visitas-do-site): os seis indicadores do período com a comparação ao
  # anterior, o gráfico de visitas e as prévias de clientes abertas no período (previews.devbatista.com,
  # fora dos números do site). O cálculo é o SiteVisits::Stats, o mesmo das tools do MCP.
  # Cache de até 15 minutos, menos em Hoje e Ontem, que mudam a cada visita.
  class SiteVisitsController < ApplicationController
    LIVE_PERIODS = %w[hoje ontem].freeze
    PREVIEWS_LIMIT = 25

    def index
      authorize :site_visit, :index?
      @period = SiteVisits::Stats.period(params[:periodo])
      @periods = SiteVisits::Stats::PERIODS.invert.to_a
      @empty = !SiteVisit.property_site.exists?
      return if @empty

      @summary, @previews =
        if LIVE_PERIODS.include?(@period.key) then numbers
        else Rails.cache.fetch([ "visitas-do-site", "v2", @period.key, Date.current ], expires_in: ::DashboardController::CACHE_TTL) { numbers }
        end
    end

    private

    def numbers
      [ SiteVisits::Stats.new(@period).summary.merge(generated_at: Time.current),
        SiteVisits::Stats.new(@period, "area" => "previews").by_dimension("previa", limit: PREVIEWS_LIMIT) ]
    end
  end
end
