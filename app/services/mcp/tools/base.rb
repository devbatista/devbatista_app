# Base das tools do MCP. Cada tool roda como o usuário do token (Current.user), com as
# mesmas permissões e a mesma auditoria da tela:
#
#   class Mcp::Tools::BuscarLeads < Mcp::Tools::Base
#     tool_name "buscar_leads"
#     description "..."
#     read_only
#
#     def execute(termo: nil)
#       { leads: policy_scope(Lead).search(termo).map { ... } }
#     end
#   end
#
# `execute` devolve um Hash, que vai ao Claude como JSON. Permissão negada, registro
# inexistente, erro de validação e `fail!` voltam como resultado de erro legível, para o
# Claude corrigir e tentar de novo; qualquer outra exceção vira "Internal error" e vai para o log.
module Mcp
  module Tools
    class Base < MCP::Tool
      # Recusa com mensagem para o Claude (regra de negócio, não erro do sistema).
      class Failure < StandardError; end

      PER_PAGE = 25
      MAX_PER_PAGE = 50

      # Propriedades de paginação para o input_schema das listagens.
      PAGINATION = {
        pagina: { type: "integer", minimum: 1, description: "Página, começando em 1" },
        por_pagina: { type: "integer", minimum: 1, maximum: MAX_PER_PAGE, description: "Itens por página (padrão #{PER_PAGE})" }
      }.freeze

      class << self
        def call(server_context:, **args)
          user = User.active.find_by(id: server_context.auth_info&.subject)
          return error("Usuário do token não encontrado ou desativado. Conecte o Claude de novo.") unless user

          Current.set(user: user) { respond(new(user).execute(**args)) }
        rescue Failure => e
          error(e.message)
        rescue Pundit::NotAuthorizedError
          error("Sem permissão para esta ação.")
        rescue ActiveRecord::RecordNotFound
          error("Registro não encontrado.")
        rescue ActiveRecord::RecordInvalid => e
          error("Não foi possível salvar: #{e.record.errors.full_messages.to_sentence}.")
        end

        # Só consulta, não altera nada.
        def read_only
          annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)
        end

        # Cria ou altera, mas nunca exclui nem sai do sistema.
        def writes
          annotations(read_only_hint: false, destructive_hint: false, open_world_hint: false)
        end

        private

        def respond(data)
          MCP::Tool::Response.new([ { type: "text", text: data.to_json } ])
        end

        def error(message)
          MCP::Tool::Response.new([ { type: "text", text: message } ], error: true)
        end
      end

      attr_reader :user

      def initialize(user)
        @user = user
      end

      def execute(**)
        raise NotImplementedError
      end

      private

      def authorize(record, query = :show?)
        Pundit.authorize(user, record, query)
      end

      def policy_scope(scope)
        Pundit.policy_scope!(user, scope)
      end

      def fail!(message)
        raise Failure, message
      end

      # Página da listagem e o bloco de paginação da resposta.
      def paginate(scope, pagina, por_pagina)
        per = (por_pagina || PER_PAGE).clamp(1, MAX_PER_PAGE)
        page = [ pagina.to_i, 1 ].max
        total = scope.unscope(:order, :select).count
        [ scope.offset((page - 1) * per).limit(per),
          { pagina: page, por_pagina: per, total: total, paginas: [ (total / per.to_f).ceil, 1 ].max } ]
      end

      # Centavos → reais, como número (o Claude formata).
      def reais(cents)
        cents && (cents / 100.0)
      end

      # Link para a tela do sistema, para o Claude oferecer ao usuário.
      def link(route, *args, **params)
        Rails.application.routes.url_helpers.public_send(:"#{route}_url", *args, **ActionMailer::Base.default_url_options, **params)
      end
    end
  end
end
