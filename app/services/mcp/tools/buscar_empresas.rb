module Mcp
  module Tools
    class BuscarEmpresas < Base
      tool_name "buscar_empresas"
      title "Buscar empresas"
      description <<~TEXT.squish
        Busca empresas (clientes e prospects) por nome fantasia, razão social ou CNPJ. Devolve o id, que
        oportunidades e propostas exigem, e o contato principal.
      TEXT
      read_only
      input_schema(
        properties: {
          termo: { type: "string", description: "Parte do nome, da razão social ou do CNPJ" },
          status: { type: "string", enum: Company::STATUS_LABELS.keys, description: "prospect, active (cliente ativo) ou inactive" },
          **PAGINATION
        },
        additionalProperties: false
      )

      def execute(termo: nil, status: nil, pagina: nil, por_pagina: nil)
        authorize(Company, :index?)
        scope = policy_scope(Company).by_name
        scope = scope.search(termo) if termo.present?
        scope = scope.where(status: status) if status
        companies, pager = paginate(scope.includes(:contacts), pagina, por_pagina)

        { empresas: companies.map { |company| company_data(company) }, paginacao: pager }
      end

      private

      def company_data(company)
        contact = company.contacts.find(&:primary?) || company.contacts.first
        {
          id: company.id, nome: company.trade_name, razao_social: company.legal_name, cnpj: company.formatted_cnpj,
          status: company.status, status_rotulo: company.status_label,
          cidade: [ company.city, company.state ].compact_blank.join("/").presence,
          contato_principal: contact && { id: contact.id, nome: contact.name, email: contact.email,
                                          telefone: contact.phone, whatsapp: contact.whatsapp },
          link: link(:company, company)
        }
      end
    end
  end
end
