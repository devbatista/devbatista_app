module Management
  # Indicadores (RF 40): os 14 números calculados dos registros, com a definição de cada um e a
  # comparação com o período anterior. Os de dinheiro só aparecem para quem vê o financeiro; os
  # demais seguem a área de origem (clientes, comercial, horas). Cache de até 15 minutos.
  class IndicatorsController < ApplicationController
    include FinancePeriod

    def show
      authorize :report, :index?
      set_period(back: 12, forward: 0)
      @previous_label = @period.match?(/\A\d{4}-\d{2}\z/) ? I18n.l(@range.first << 1, format: "%B").downcase : "período anterior"
      @financial = current_user.sees_financials?
      @data = Rails.cache.fetch([ "indicadores", @period, Date.current ], expires_in: ::DashboardController::CACHE_TTL) { build_data }
    end

    private

    def build_data
      now = Metrics.new(@range)
      before = Metrics.new(Metrics.previous_range(@range))
      close = [ @range.last, Date.current ].min
      clients = Metrics.clients_at(close)
      previous_clients = Metrics.clients_at(before.range.last)
      hours = now.hours_by_company
      names = Company.where(id: hours.keys + now.revenue_by_company.keys).pluck(:id, :trade_name).to_h
      {
        generated_at: Time.current, until: close,
        mrr: [ now.mrr_end, before.mrr_end ],
        billed: [ now.billing[:billed], before.billing[:billed] ],
        result: [ now.result_cents, before.result_cents ],
        margin: [ now.margin_percent, before.margin_percent ],
        ticket: [ (now.billing[:billed] / clients if clients.positive?), (before.billing[:billed] / previous_clients if previous_clients.positive?) ],
        infrastructure: now.infrastructure_cents,
        clients: [ clients, previous_clients ],
        new_clients: now.new_clients.count, acquisition: now.acquisition_cents,
        cac: [ now.cac_cents, before.cac_cents ],
        churn: [ now.churn.except(:before, :after), before.churn.except(:before, :after) ],
        proposals: now.open_proposals,
        hours: hours.sum { |_, m| m }, hours_top: hours.max_by { |_, m| m }&.then { |id, m| [ names[id] || "Sem cliente", m ] },
        by_company: now.revenue_by_company.map { |id, v| [ names[id], v ] }.sort_by { |_, v| -v },
        by_service: now.revenue_by_service.sort_by { |_, v| -v },
        conversion: [ now.conversion, before.conversion.slice(:rate) ]
      }
    end
  end
end
