# Documentos de descoberta do OAuth, publicados em /.well-known (OauthMetadataController):
# - recurso protegido (RFC 9728): o /mcp e quem emite tokens para ele;
# - servidor de autorização (RFC 8414): os endpoints do Doorkeeper.
# O cliente MCP chega ao primeiro pelo WWW-Authenticate do 401 e ao segundo pelo primeiro.
module Mcp
  module Metadata
    SCOPES = %w[mcp].freeze
    # Para onde o claude.ai devolve o código de autorização (app OAuth em lib/tasks/mcp.rake).
    CLAUDE_REDIRECT_URIS = %w[https://claude.ai/api/mcp/auth_callback https://claude.com/api/mcp/auth_callback].freeze

    def self.base_url
      Rails.configuration.x.mcp.base_url
    end

    def self.protected_resource
      MCP::Server::OAuth::ProtectedResourceMetadata.new(
        resource: "#{base_url}/mcp", authorization_servers: [ base_url ], scopes_supported: SCOPES,
        resource_name: "Admin DevBatista"
      )
    end

    def self.authorization_server
      {
        issuer: base_url,
        authorization_endpoint: "#{base_url}/oauth/authorize",
        token_endpoint: "#{base_url}/oauth/token",
        revocation_endpoint: "#{base_url}/oauth/revoke",
        response_types_supported: %w[code],
        grant_types_supported: %w[authorization_code refresh_token],
        code_challenge_methods_supported: %w[S256],
        token_endpoint_auth_methods_supported: %w[client_secret_basic client_secret_post],
        scopes_supported: SCOPES
      }
    end
  end
end
