# Confere o token do cabeçalho Authorization: Bearer de cada requisição ao /mcp.
# Devolve um MCP::Server::OAuth::AccessToken com o id do usuário em `subject`; as tools
# rodam como esse usuário. Token recusado vira 401 com WWW-Authenticate, pela própria gem.
#
# Aceita:
# - tokens OAuth do Doorkeeper (config/initializers/doorkeeper.rb), válidos e com escopo mcp;
# - o token fixo de desenvolvimento (config.x.mcp.dev_token), que não existe em produção.
#   Entra como o usuário de MCP_DEV_USER (e-mail) ou o primeiro administrador ativo.
#
# Na v1 o MCP é só do administrador (docs/specs/mcp-comercial/README.md).
module Mcp
  class TokenVerifier
    def verify(token)
      if dev_token?(token)
        user = dev_user
        access = nil
      else
        access = oauth_token(token)
        user = access && User.find_by(id: access.resource_owner_id)
      end
      raise MCP::Server::OAuth::InvalidTokenError, "Token inválido ou expirado" unless user&.active? && user.admin?

      MCP::Server::OAuth::AccessToken.new(
        token: token, client_id: access ? access.application.uid : "dev", subject: user.id,
        scopes: access ? access.scopes.to_a : Metadata::SCOPES, expires_at: access&.expires_at&.to_i
      )
    end

    private

    def dev_token?(token)
      expected = Rails.configuration.x.mcp.dev_token
      expected.present? && ActiveSupport::SecurityUtils.secure_compare(token.to_s, expected)
    end

    def dev_user
      email = ENV["MCP_DEV_USER"].presence
      email ? User.find_by(email: email.strip.downcase) : User.active.joins(:role).where(roles: { key: "admin" }).order(:created_at).first
    end

    # Como o Doorkeeper::OAuth::Token.authenticate: o uso do token novo revoga o refresh token anterior.
    def oauth_token(token)
      access = Doorkeeper::AccessToken.by_token(token)
      return unless access&.acceptable?(Metadata::SCOPES)

      access.revoke_previous_refresh_token!
      access
    end
  end
end
