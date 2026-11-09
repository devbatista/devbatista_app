# Período e filtros das tools das visitas do site (docs/specs/visitas-do-site, Tools do MCP).
# O cálculo é o SiteVisits::Stats, o mesmo da tela.
module Mcp
  module Tools
    module SiteVisitsData
      PERIOD_PROPERTIES = {
        periodo: { type: "string", enum: SiteVisits::Stats::PERIODS.keys,
                   description: "Período (padrão 7d): #{SiteVisits::Stats::PERIODS.map { |k, v| "#{k} = #{v}" }.join(', ')}" },
        de: { type: "string", format: "date", description: "Início de um intervalo livre, AAAA-MM-DD (até #{SiteVisits::Stats::MAX_DAYS} dias). Com de/ate, periodo é ignorado" },
        ate: { type: "string", format: "date", description: "Fim do intervalo livre, AAAA-MM-DD" }
      }.freeze

      FILTER_PROPERTIES = {
        canal: { type: "string", enum: SiteVisit::CHANNEL_LABELS.keys,
                 description: "Canal de origem: #{SiteVisit::CHANNEL_LABELS.map { |k, v| "#{k} = #{v}" }.join(', ')}" },
        origem: { type: "string", description: "Host da referência sem www (google.com, instagram.com, chatgpt.com) ou direto" },
        utm_source: { type: "string" }, utm_medium: { type: "string" }, utm_campaign: { type: "string" },
        pagina: { type: "string", description: "Caminho exato (/solucoes): as visitas que passaram pela página" },
        pagina_entrada: { type: "string", description: "Caminho da primeira página da visita" },
        dispositivo: { type: "string", enum: SiteVisit::DEVICE_TYPE_LABELS.keys }
      }.freeze

      LIMIT = { type: "integer", minimum: 1, maximum: Base::MAX_PER_PAGE, description: "Linhas (padrão #{Base::PER_PAGE}, até #{Base::MAX_PER_PAGE})" }.freeze

      private

      def stats(periodo, de, ate, **filters)
        authorize(:site_visit, :index?)
        SiteVisits::Stats.new(SiteVisits::Stats.period(periodo, de: de, ate: ate, strict: true), filters)
      rescue SiteVisits::Stats::Invalid => e
        fail!(e.message)
      end

      def limit(value)
        (value || Base::PER_PAGE).clamp(1, Base::MAX_PER_PAGE)
      end

      # Invalid do cálculo vira recusa legível para o Claude corrigir.
      def calculate
        yield
      rescue SiteVisits::Stats::Invalid => e
        fail!(e.message)
      end
    end
  end
end
