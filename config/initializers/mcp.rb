# Servidor MCP em /mcp (docs/specs/mcp-comercial/README.md).
# Erro inesperado numa tool volta ao Claude só como "Internal error"; o detalhe vai para o log.
MCP.configure do |config|
  config.exception_reporter = lambda do |exception, server_context|
    Rails.error.report(exception, handled: true, source: "mcp", context: { mcp: server_context.inspect.truncate(500) })
  end
end
