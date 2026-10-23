# Servidor de autorização OAuth 2.1 do MCP (docs/specs/mcp-comercial/README.md): o conector do
# Claude pede acesso em /oauth/authorize, a pessoa entra com o login do sistema e autoriza, e o
# Claude troca o código por um token em /oauth/token. O token vale para o /mcp (Mcp::TokenVerifier).
#
# O app OAuth do Claude é cadastrado por `bin/rails mcp:oauth_app` (lib/tasks/mcp.rake).
Doorkeeper.configure do
  orm :active_record

  # Sem sessão, guarda o destino e manda para o login; o Devise volta para cá depois.
  resource_owner_authenticator do
    current_user || begin
      session["user_return_to"] = request.fullpath
      redirect_to new_user_session_url
    end
  end

  # Na v1 o MCP é só do administrador.
  authorize_resource_owner_for_client do |_client, user|
    user.active? && user.admin?
  end

  grant_flows %w[authorization_code]
  use_refresh_token
  access_token_expires_in 1.hour
  authorization_code_expires_in 5.minutes
  pkce_code_challenge_methods %w[S256]

  default_scopes :mcp
  enforce_configured_scopes

  # O banco guarda só o hash de tokens, códigos e do secret do app.
  hash_token_secrets
  hash_application_secrets

  # O Claude Code recebe o código em http://localhost:<porta>/callback.
  force_ssl_in_redirect_uri { |uri| !Rails.env.development? && !uri.host.in?(%w[localhost 127.0.0.1]) }
end

Rails.application.config.to_prepare do
  Doorkeeper::AuthorizationsController.layout "auth"
end
