# Escritório de agentes de IA (docs/specs/escritorio-agentes): os agentes do Claude, os eventos que
# eles registram pelo MCP e as ordens deixadas pelo administrador para a próxima execução.
class CreateAgentTables < ActiveRecord::Migration[8.1]
  def change
    create_table :agents, id: :uuid do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.string :title, null: false
      t.string :room, null: false
      t.integer :position, null: false, default: 0
      t.string :outfit_color, null: false
      t.string :hair_color, null: false
      t.string :skin_color, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :agents, :key, unique: true

    create_table :agent_events, id: :uuid do |t|
      t.references :agent, type: :uuid, null: false, foreign_key: true, index: false
      t.string :status, null: false
      t.string :title, null: false
      t.text :summary
      t.boolean :needs_approval, null: false, default: false
      t.string :decision
      t.datetime :decided_at
      t.references :decided_by, type: :uuid, foreign_key: { to_table: :users }
      t.text :decision_note
      t.datetime :decision_read_at
      t.jsonb :payload
      t.timestamps
      t.check_constraint "needs_approval = (status = 'awaiting_approval')", name: "agent_events_approval_status"
      t.check_constraint "needs_approval = (decision IS NOT NULL)", name: "agent_events_approval_decision"
    end
    add_index :agent_events, %i[agent_id created_at], order: { created_at: :desc }
    add_index :agent_events, :agent_id, where: "decision = 'pending'", name: "index_agent_events_pending_decision"
    add_index :agent_events, :agent_id, where: "decision IN ('approved', 'rejected') AND decision_read_at IS NULL",
                                        name: "index_agent_events_unread_decision"

    create_table :agent_orders, id: :uuid do |t|
      t.references :agent, type: :uuid, null: false, foreign_key: true, index: false
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.text :body, null: false
      t.string :status, null: false, default: "pending"
      t.text :response
      t.datetime :delivered_at
      t.datetime :completed_at
      t.timestamps
    end
    add_index :agent_orders, %i[agent_id created_at]
    add_index :agent_orders, :agent_id, where: "status = 'pending'", name: "index_agent_orders_pending"
  end
end
