# Chama uma tool do MCP direto, como o usuário dado (sem passar pelo HTTP).
module McpHelpers
  def mcp_context(user)
    token = MCP::Server::OAuth::AccessToken.new(token: "x", subject: user&.id)
    MCP::ServerContext.new({}, progress: nil, notification_target: nil, auth_info: token)
  end

  def call_tool(tool, user, **args)
    tool.call(**args, server_context: mcp_context(user))
  end

  # Resposta de sucesso como Hash; falha o teste se a tool devolveu erro.
  def tool_data(tool, user, **args)
    response = call_tool(tool, user, **args)
    raise "Tool devolveu erro: #{response.content.dig(0, :text)}" if response.error?

    JSON.parse(response.content.dig(0, :text))
  end
end

RSpec.configure do |config|
  config.include McpHelpers
end
