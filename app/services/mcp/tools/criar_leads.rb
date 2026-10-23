module Mcp
  module Tools
    # Cadastro de leads em lote, a partir de uma lista colada pelo usuário.
    # Tudo ou nada: se um lead não passa na validação, nenhum é gravado.
    class CriarLeads < Base
      include CommercialData

      MAX_LEADS = 100
      STATUSES = Lead::OPEN_STATUSES

      tool_name "criar_leads"
      title "Cadastrar leads"
      description <<~TEXT.squish
        Cadastra até #{MAX_LEADS} leads de uma vez. Campos comuns a todos (origem, serviço, responsável) podem ir em
        `padroes`. Antes de gravar, procura leads já cadastrados com o mesmo e-mail, nome ou empresa: por padrão
        pula esses e informa quais foram. É tudo ou nada: se um lead tiver erro, nenhum é gravado e a resposta diz qual.
        Com `simular: true`, valida e mostra o resultado sem gravar; use isso antes de listas grandes.
        Não invente dados: o que não veio na lista fica vazio. Colunas sem campo próprio (segmento, site, Instagram)
        vão em observacoes, uma por linha, como "Rótulo: valor".
      TEXT
      writes
      lead_properties = LEAD_PROPERTIES.merge(status: { type: "string", enum: STATUSES, description: "Padrão: new" })
      input_schema(
        properties: {
          leads: { type: "array", minItems: 1, maxItems: MAX_LEADS,
                   items: { type: "object", properties: lead_properties, additionalProperties: false } },
          padroes: { type: "object", properties: lead_properties.except(:nome), additionalProperties: false,
                     description: "Valores para todos os leads; o que vier no lead prevalece" },
          pular_duplicados: { type: "boolean", description: "Padrão: true. Com false, cadastra mesmo se já existir" },
          simular: { type: "boolean", description: "Valida sem gravar. Padrão: false" }
        },
        required: [ "leads" ],
        additionalProperties: false
      )

      def execute(leads:, padroes: {}, pular_duplicados: true, simular: false)
        authorize(Lead, :create?)
        created = []
        skipped = []

        Lead.transaction do
          leads.each_with_index do |row, index|
            attrs = attributes_from(padroes.merge(row), LEAD_FIELDS)
            attrs[:status] = row[:status] || padroes[:status] || "new"
            attrs[:user_id] ||= user.id
            if pular_duplicados && (existing = duplicate_of(attrs))
              skipped << { linha: index + 1, nome: attrs[:name], ja_cadastrado: lead_data(existing) }
              next
            end

            lead = authorize(Lead.new(attrs), :create?)
            fail!("Lead #{index + 1} (#{attrs[:name] || 'sem nome'}): #{lead.errors.full_messages.to_sentence}. Nada foi gravado.") unless lead.save
            created << lead_data(lead)
          end
          raise ActiveRecord::Rollback if simular
        end

        { simulacao: simular, gravados: simular ? 0 : created.size, leads: created, pulados_por_duplicidade: skipped }
      end

      private

      # Mesmo e-mail, ou mesmo nome/empresa (sem acento e sem diferenciar maiúsculas).
      def duplicate_of(attrs)
        scope = Lead.all
        email = attrs[:email].to_s.strip.downcase.presence
        return scope.find_by(email: email) || by_name(scope, attrs) if email

        by_name(scope, attrs)
      end

      def by_name(scope, attrs)
        names = [ attrs[:name], attrs[:company_name] ].compact_blank.map(&:strip).uniq
        return if names.empty?

        clauses = names.map { "unaccent(leads.name) ILIKE unaccent(?) OR unaccent(leads.company_name) ILIKE unaccent(?)" }
        values = names.flat_map { |name| [ Lead.sanitize_sql_like(name) ] * 2 }
        scope.where(clauses.join(" OR "), *values).first
      end
    end
  end
end
