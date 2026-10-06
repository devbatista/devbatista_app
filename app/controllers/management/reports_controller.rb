module Management
  # Relatórios (RF 38): o catálogo dos 19, só com os que o perfil pode ver, e o relatório aberto
  # logo abaixo, com filtros (período ou datas; cliente e serviço nos financeiros) e CSV.
  class ReportsController < ApplicationController
    include FinancePeriod

    MAX_DAYS = 3 * 366

    before_action :set_catalog

    def index; end

    def show
      @report = ReportCatalog.find(params[:id])
      raise ActiveRecord::RecordNotFound unless @report
      raise Pundit::NotAuthorizedError unless @report.visible_to?(current_user)

      set_report_period
      @result = ReportCatalog.new(@report, range: @range, user: current_user, scope: ->(model) { policy_scope(model) },
                                           company_id: params[:cliente], service_id: params[:servico]).result
      @filters = {
        company: (Company.find_by(id: params[:cliente]) if @report.financial && params[:cliente].present?),
        service: (Service.find_by(id: params[:servico]) if @report.financial && params[:servico].present?)
      }

      respond_to do |format|
        format.html { render :index }
        format.csv { send_data csv, filename: "#{@report.key}-#{@range.first.strftime('%Y%m%d')}-#{@range.last.strftime('%Y%m%d')}.csv", type: "text/csv; charset=utf-8" }
      end
    end

    private

    def set_catalog
      authorize :report, :index?
      @reports = ReportCatalog.visible_to(current_user)
    end

    # Período pronto do seletor ou "Personalizado", com "de" e "até" (intervalo de até 3 anos).
    def set_report_period
      set_period(back: 12, forward: 0)
      @periods += [ [ "Personalizado (de/até)", "personalizado" ] ]
      return unless params[:periodo] == "personalizado"

      from = Date.iso8601(params[:de].to_s) rescue nil # rubocop:disable Style/RescueModifier
      to = Date.iso8601(params[:ate].to_s) rescue nil # rubocop:disable Style/RescueModifier
      return unless from && to && from <= to && (to - from) <= MAX_DAYS

      @range = from..to
      @period = "personalizado"
      @period_label = "#{I18n.l(from)} a #{I18n.l(to)}"
    end

    def csv
      rows = @result.rows.map { |row| row.each_with_index.map { |value, i| csv_value(value, @result.columns[i].type) } }
      rows << @result.footer.each_with_index.map { |value, i| csv_value(value, @result.columns[i].type) } if @result.footer
      CsvExport.generate(@result.columns.map(&:label), rows)
    end

    def csv_value(value, type)
      return value if value.nil? || value == ""

      case type
      when :money then CsvExport.money(value)
      when :hours then (value / 60.0).round(2)
      when :percent then value.to_f.round(1)
      else value
      end
    end
  end
end
