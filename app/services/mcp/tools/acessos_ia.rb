module Mcp
  module Tools
    # Robôs e agentes de IA que buscaram páginas do site, servidos e bloqueados.
    class AcessosIa < Base
      include SiteVisitsData

      tool_name "acessos_ia"
      title "Acessos de IA ao site"
      description <<~TEXT.squish
        Páginas do site devbatista.com buscadas por robôs e agentes de IA no período, agrupadas por empresa
        (padrão), agente, tipo, pagina ou dia. Tipos: training (coleta para treinar modelos), search (índice de
        busca com IA), user (uma pessoa perguntou algo à IA e ela abriu a página para responder) e agent
        (navegação autônoma, requisição assinada). Verificação: signed (assinada, ainda não conferida),
        ip_verified (IP nas faixas oficiais), declared (só o user agent) e spoofed (user agent de um robô
        conhecido vindo de IP fora das faixas: falso, fica fora dos totais e aparece em "falsos"). O site
        bloqueia os robôs de treino (403): esses aparecem como bloqueados, a página não foi entregue. Traz
        também as visitas de pessoas que chegaram por um assistente de IA, para comparar quem a IA leu com
        quem a IA mandou. Acesso de IA não é visita de pessoa. A IA do Google (Gemini, AI Overviews) usa o
        Googlebot e não aparece aqui.
      TEXT
      read_only
      input_schema(
        properties: {
          agrupar: { type: "string", enum: SiteVisits::Stats::AI_GROUPS },
          **PERIOD_PROPERTIES,
          empresa: { type: "string", description: "OpenAI, Anthropic, Perplexity, Meta…" },
          tipo: { type: "string", enum: AiHit::KIND_LABELS.keys },
          verificacao: { type: "string", enum: AiHit::VERIFICATION_LABELS.keys },
          pagina: { type: "string", description: "Caminho exato (/solucoes)" },
          limite: LIMIT
        },
        additionalProperties: false
      )

      def execute(agrupar: "empresa", periodo: nil, de: nil, ate: nil, limite: nil, **filters)
        stats = stats(periodo, de, ate)
        calculate { stats.ai_hits(group: agrupar, filters: filters, limit: limit(limite)) }
      end
    end
  end
end
