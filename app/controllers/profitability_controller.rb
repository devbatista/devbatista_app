# Rentabilidade por cliente (RF 39): receita da competência − custos diretos, antes da mão de
# obra. Ranking de todos os clientes com receita ou custo no período e o detalhe de um deles
# (?cliente=ID), com a lista dos custos que compõem o total. Só Administrador e Financeiro.
class ProfitabilityController < ApplicationController
  include FinancePeriod

  SORTS = {
    "margem" => [ "Maior margem R$", ->(r) { -r[:margin] } ],
    "margem_pct" => [ "Maior margem %", ->(r) { -(r[:margin_percent] || -Float::INFINITY) } ],
    "menor_pct" => [ "Menor margem %", ->(r) { r[:margin_percent] || -Float::INFINITY } ],
    "receita" => [ "Maior receita", ->(r) { -r[:revenue] } ]
  }.freeze

  def show
    authorize :report, :profitability?
    set_period(back: 12, forward: 0)
    @sort = params[:ordem].presence_in(SORTS.keys) || "margem"
    @rows = Metrics.new(@range).profitability.sort_by { |r| [ SORTS[@sort].last.call(r), r[:company].trade_name ] }
    @totals = { revenue: @rows.sum { |r| r[:revenue] }, cost: @rows.sum { |r| r[:cost] } }
    @totals[:margin] = @totals[:revenue] - @totals[:cost]

    respond_to do |format|
      format.html do
        @detail = @rows.find { |r| r[:company].id.to_s == params[:cliente] }
        @detail_hours = TimeEntry.where(company: @detail[:company], worked_on: @range).sum(:minutes) if @detail
      end
      format.csv { send_data csv, filename: "rentabilidade-#{@period}.csv", type: "text/csv; charset=utf-8" }
    end
  end

  private

  # Uma linha por custo de cada cliente; cliente sem custo sai numa linha só.
  def csv
    rows = @rows.flat_map do |r|
      base = [ r[:company].trade_name, CsvExport.money(r[:revenue]), CsvExport.money(r[:cost]), CsvExport.money(r[:margin]), r[:margin_percent] ]
      lines = r[:lines].presence || [ nil ]
      lines.map { |c| base + (c ? [ c[:label], c[:origin], CsvExport.money(c[:cents]) ] : [ "", "", "" ]) }
    end
    CsvExport.generate([ "Cliente", "Receita", "Custos diretos", "Margem R$", "Margem %", "Custo", "Origem do custo", "Valor do custo" ], rows)
  end
end
