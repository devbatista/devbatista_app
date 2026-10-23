# App OAuth do conector do Claude (docs/specs/mcp-comercial/README.md).
#
#   bin/rails mcp:oauth_app                 cria o app e mostra Client ID e Client Secret
#   ROTATE=1 bin/rails mcp:oauth_app        gera um secret novo (o anterior para de valer)
#   REDIRECT_URIS="https://a https://b" ... troca as URLs de retorno aceitas
#
# O secret fica só com hash no banco: aparece uma vez, na criação ou na troca.
namespace :mcp do
  desc "Cria ou atualiza o app OAuth do conector do Claude e mostra as credenciais"
  task oauth_app: :environment do
    app = Doorkeeper::Application.find_or_initialize_by(name: "Claude")
    app.redirect_uri = ENV.fetch("REDIRECT_URIS", app.redirect_uri.presence || Mcp::Metadata::CLAUDE_REDIRECT_URIS.join(" ")).split.join("\n")
    app.scopes = Mcp::Metadata::SCOPES.join(" ")
    app.confidential = true
    app.renew_secret if app.persisted? && ENV["ROTATE"].present?
    app.save!

    puts "App OAuth \"#{app.name}\""
    puts "  URL do servidor MCP: #{Mcp::Metadata.base_url}/mcp"
    puts "  Client ID:           #{app.uid}"
    puts "  Client Secret:       #{app.plaintext_secret || '(já gerado; para trocar, rode com ROTATE=1)'}"
    puts "  URLs de retorno:     #{app.redirect_uri.split.join(', ')}"
  end
end
