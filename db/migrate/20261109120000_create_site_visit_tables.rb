# Visitas do site (docs/specs/visitas-do-site): as visitas de pessoas ao devbatista.com, as páginas
# vistas em cada uma, o sal diário do hash do visitante e os acessos de robôs e agentes de IA.
# Nada aqui guarda IP: o visitante é um hash que muda todo dia.
class CreateSiteVisitTables < ActiveRecord::Migration[8.1]
  def change
    create_table :site_visits, id: :uuid do |t|
      t.string :visitor_hash, null: false
      t.datetime :started_at, null: false
      t.datetime :last_seen_at, null: false
      t.integer :pageviews_count, null: false, default: 0
      t.integer :duration_seconds, null: false, default: 0
      t.string :entry_path, null: false
      t.string :exit_path, null: false
      t.string :referrer_host
      t.string :utm_source
      t.string :utm_medium
      t.string :utm_campaign
      t.string :utm_content
      t.string :utm_term
      t.string :channel, null: false
      t.string :ai_assistant
      t.string :device_type, null: false
      t.string :browser
      t.string :os
      t.timestamps
    end
    add_index :site_visits, %i[visitor_hash last_seen_at], order: { last_seen_at: :desc }
    add_index :site_visits, :started_at

    create_table :site_pageviews, id: :uuid do |t|
      t.references :site_visit, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.string :client_id, null: false
      t.string :path, null: false
      t.datetime :occurred_at, null: false
      t.integer :duration_seconds
      t.timestamps
    end
    add_index :site_pageviews, :client_id, unique: true
    add_index :site_pageviews, :occurred_at

    create_table :site_visit_salts, id: :uuid do |t|
      t.date :day, null: false
      t.string :salt, null: false
      t.timestamps
    end
    add_index :site_visit_salts, :day, unique: true

    create_table :ai_hits, id: :uuid do |t|
      t.string :agent, null: false
      t.string :agent_name, null: false
      t.string :company, null: false
      t.string :kind, null: false
      t.string :verification, null: false
      t.string :signature_agent
      t.string :path, null: false
      t.boolean :accepts_markdown, null: false, default: false
      t.datetime :occurred_at, null: false
      t.timestamps
    end
    add_index :ai_hits, :occurred_at
  end
end
