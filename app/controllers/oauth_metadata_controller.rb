# Descoberta do OAuth do MCP (Mcp::Metadata). Pública: só descreve endpoints.
class OauthMetadataController < ActionController::API
  def protected_resource
    render json: Mcp::Metadata.protected_resource.to_h
  end

  def authorization_server
    render json: Mcp::Metadata.authorization_server
  end
end
