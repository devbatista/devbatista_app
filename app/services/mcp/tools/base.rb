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
# inexistente e erro de validação voltam como resultado de erro legível, para o Claude
# corrigir e tentar de novo; qualquer outra exceção vira "Internal error" e vai para o log.
module Mcp
  module Tools
    class Base < MCP::Tool
      class << self
        def call(server_context:, **args)
          user = User.active.find_by(id: server_context.auth_info&.subject)
          return error("Usuário do token não encontrado ou desativado. Conecte o Claude de novo.") unless user

          Current.set(user: user) { respond(new(user).execute(**args)) }
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

      # Centavos → reais, como número (o Claude formata).
      def reais(cents)
        cents && (cents / 100.0)
      end
    end
  end
end
