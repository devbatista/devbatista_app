# Confere o token do cabeçalho Authorization: Bearer de cada requisição ao /mcp.
# Devolve um MCP::Server::OAuth::AccessToken com o id do usuário em `subject`; as tools
# rodam como esse usuário. Token recusado vira 401 com WWW-Authenticate, pela própria gem.
#
# Fase 1: só o token fixo de desenvolvimento (config.x.mcp.dev_token), que não existe em
# produção. Entra como o usuário de MCP_DEV_USER (e-mail) ou o primeiro administrador ativo.
# Fase 4: tokens OAuth do Doorkeeper.
#
# Na v1 o MCP é só do administrador (docs/specs/mcp-comercial/README.md).
module Mcp
  class TokenVerifier
    def verify(token)
      user = dev_token?(token) ? dev_user : nil
      raise MCP::Server::OAuth::InvalidTokenError, "Token inválido ou expirado" unless user&.active? && user.admin?

      MCP::Server::OAuth::AccessToken.new(token: token, client_id: "dev", subject: user.id)
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
  end
end
