# OAuth 2.1 do servidor MCP (Doorkeeper), para o conector do Claude (docs/specs/mcp-comercial).
# Tabelas do gerador do Doorkeeper com PKCE, ids em UUID e o dono dos tokens ligado a users.
# Tokens, refresh tokens e o secret dos apps ficam com hash (config/initializers/doorkeeper.rb).
class CreateDoorkeeperTables < ActiveRecord::Migration[8.1]
  def change
    create_table :oauth_applications, id: :uuid do |t|
      t.string :name, null: false
      t.string :uid, null: false
      t.string :secret, null: false
      t.text :redirect_uri, null: false
      t.string :scopes, null: false, default: ""
      t.boolean :confidential, null: false, default: true
      t.timestamps
    end
    add_index :oauth_applications, :uid, unique: true

    create_table :oauth_access_grants, id: :uuid do |t|
      t.references :resource_owner, type: :uuid, null: false, foreign_key: { to_table: :users }
      t.references :application, type: :uuid, null: false, foreign_key: { to_table: :oauth_applications }
      t.string :token, null: false
      t.integer :expires_in, null: false
      t.text :redirect_uri, null: false
      t.string :scopes, null: false, default: ""
      t.string :code_challenge
      t.string :code_challenge_method
      t.datetime :created_at, null: false
      t.datetime :revoked_at
    end
    add_index :oauth_access_grants, :token, unique: true

    create_table :oauth_access_tokens, id: :uuid do |t|
      t.references :resource_owner, type: :uuid, foreign_key: { to_table: :users }
      t.references :application, type: :uuid, null: false, foreign_key: { to_table: :oauth_applications }
      t.string :token, null: false
      t.string :refresh_token
      t.integer :expires_in
      t.string :scopes
      t.datetime :created_at, null: false
      t.datetime :revoked_at
      # Com a coluna, o refresh token anterior só é revogado quando o novo access token é usado.
      t.string :previous_refresh_token, null: false, default: ""
    end
    add_index :oauth_access_tokens, :token, unique: true
    add_index :oauth_access_tokens, :refresh_token, unique: true
  end
end
