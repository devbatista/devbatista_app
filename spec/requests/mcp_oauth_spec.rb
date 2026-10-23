require "rails_helper"

RSpec.describe "OAuth do servidor MCP" do
  let(:admin) { create(:user) }
  let(:callback) { "https://claude.ai/api/mcp/auth_callback" }
  let!(:client) { Doorkeeper::Application.create!(name: "Claude", redirect_uri: callback, scopes: "mcp") }
  let(:secret) { client.plaintext_secret }
  let(:verifier) { SecureRandom.urlsafe_base64(48) }
  let(:challenge) { Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false) }

  def authorize_params
    { client_id: client.uid, redirect_uri: callback, response_type: "code", state: "xyz", scope: "mcp",
      code_challenge: challenge, code_challenge_method: "S256" }
  end

  # Login, consentimento e troca do código pelo token, como o claude.ai faz.
  def obtain_tokens(code_verifier: verifier)
    sign_in admin
    post oauth_authorization_path, params: authorize_params
    code = Rack::Utils.parse_query(URI(response.location).query)["code"]
    post oauth_token_path, params: { grant_type: "authorization_code", code: code, redirect_uri: callback,
                                     client_id: client.uid, client_secret: secret, code_verifier: code_verifier }
    response.parsed_body
  end

  def mcp_tools_list(token)
    headers = { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream" }
    headers["Authorization"] = "Bearer #{token}" if token
    post mcp_path, params: { jsonrpc: "2.0", id: 1, method: "tools/list" }.to_json, headers: headers
  end

  describe "descoberta" do
    it "aponta a metadata do recurso no 401 do /mcp" do
      mcp_tools_list(nil)
      expect(response).to have_http_status(:unauthorized)
      expect(response.headers["WWW-Authenticate"]).to include('resource_metadata="https://www.example.com/.well-known/oauth-protected-resource/mcp"')
    end

    it "publica o recurso protegido e o servidor de autorização" do
      get "/.well-known/oauth-protected-resource/mcp"
      expect(response.parsed_body).to include("resource" => "https://www.example.com/mcp",
                                              "authorization_servers" => [ "https://www.example.com" ], "scopes_supported" => [ "mcp" ])

      get "/.well-known/oauth-authorization-server"
      expect(response.parsed_body).to include("issuer" => "https://www.example.com",
                                              "token_endpoint" => "https://www.example.com/oauth/token",
                                              "code_challenge_methods_supported" => [ "S256" ])
    end
  end

  describe "autorização" do
    it "manda para o login e volta para o consentimento" do
      get oauth_authorization_path, params: authorize_params
      expect(response).to redirect_to(new_user_session_path)

      post user_session_path, params: { user: { email: admin.email, password: "senha-segura-123" } }
      expect(URI(response.location).path).to eq(oauth_authorization_path)
      expect(Rack::Utils.parse_query(URI(response.location).query)).to eq(authorize_params.stringify_keys)
      follow_redirect!
      expect(response.body).to include("auth-card", "Conectar o Claude", "Autorizar", "Recusar")
    end

    it "recusa quem não é administrador" do
      sign_in create(:user, :comercial)
      get oauth_authorization_path, params: authorize_params
      expect(response.body).not_to include("Autorizar")
      post oauth_authorization_path, params: authorize_params
      expect(response.location.to_s).not_to include("code=")
    end

    it "volta ao Claude com erro quando a pessoa recusa" do
      sign_in admin
      delete oauth_authorization_path, params: authorize_params
      expect(response.location).to start_with(callback).and include("error=access_denied")
    end
  end

  describe "tokens" do
    it "troca o código por token que abre o /mcp como o usuário" do
      tokens = obtain_tokens
      expect(tokens).to include("token_type" => "Bearer", "expires_in" => 3600, "scope" => "mcp")
      mcp_tools_list(tokens["access_token"])
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("result", "tools")).to be_present
    end

    it "exige o code_verifier do PKCE" do
      expect(obtain_tokens(code_verifier: "outro-verificador-com-tamanho-suficiente-1234567890")["error"]).to eq("invalid_grant")
    end

    it "renova com o refresh token, e o anterior deixa de valer quando o novo é usado" do
      tokens = obtain_tokens
      refresh = ->(token) { post oauth_token_path, params: { grant_type: "refresh_token", refresh_token: token, client_id: client.uid, client_secret: secret } }
      refresh.call(tokens["refresh_token"])
      renewed = response.parsed_body
      expect(renewed["access_token"]).to be_present

      mcp_tools_list(renewed["access_token"])
      expect(response).to have_http_status(:ok)
      refresh.call(tokens["refresh_token"])
      expect(response.parsed_body["error"]).to eq("invalid_grant")
    end

    it "recusa token revogado, expirado ou de usuário desativado" do
      tokens = obtain_tokens
      token = Doorkeeper::AccessToken.by_token(tokens["access_token"])

      travel 61.minutes do
        mcp_tools_list(tokens["access_token"])
        expect(response).to have_http_status(:unauthorized)
      end

      admin.update!(active: false)
      mcp_tools_list(tokens["access_token"])
      expect(response).to have_http_status(:unauthorized)

      admin.update!(active: true)
      token.revoke
      mcp_tools_list(tokens["access_token"])
      expect(response).to have_http_status(:unauthorized)
    end

    it "guarda só o hash do token" do
      tokens = obtain_tokens
      expect(Doorkeeper::AccessToken.where(token: tokens["access_token"])).to be_empty
    end
  end
end
