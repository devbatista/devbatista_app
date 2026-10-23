# Endpoint /mcp: o Admin DevBatista como servidor MCP, para virar conector do Claude
# (docs/specs/mcp-comercial/README.md).
#
# App Rack montado nas rotas. Cada requisição monta um transporte Streamable HTTP stateless
# que responde em JSON (sem sessão e sem SSE). O token do cabeçalho Authorization é conferido
# pelo TokenVerifier antes de qualquer leitura do corpo; sem token válido, 401.
module Mcp
  class Endpoint
    TOOLS = [
      Tools::OpcoesComerciais
    ].freeze

    INSTRUCTIONS = <<~TEXT.squish
      Admin DevBatista é o sistema de gestão da DevBatista, uma software house. Este servidor dá acesso ao
      Comercial: leads, pipeline, oportunidades, propostas e interações. Valores em reais, datas em AAAA-MM-DD,
      ids em UUID. Antes de criar ou alterar registros, consulte opcoes_comerciais para usar as chaves aceitas.
    TEXT

    def self.call(env)
      # A auditoria marca o que veio do Claude (AuditLog#ip_address).
      Current.ip_address = "mcp:#{ActionDispatch::Request.new(env).remote_ip}"
      transport.call(env)
    end

    def self.transport
      MCP::Server::Transports::StreamableHTTPTransport.new(
        server,
        stateless: true,
        enable_json_response: true,
        serve_subscriptions_listen: false,
        token_verifier: TokenVerifier.new,
        allowed_hosts: Rails.configuration.x.mcp.allowed_hosts
      )
    end

    def self.server
      MCP::Server.new(name: "admin-devbatista", title: "Admin DevBatista", version: "1.0.0",
                      instructions: INSTRUCTIONS, tools: TOOLS)
    end
  end
end
