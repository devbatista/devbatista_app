# Conexões de cobrança: fornecedores cujas faturas entram em Despesas pela API (AWS, Cloudflare).
# - A conexão guarda só o que não é segredo (conta, centro de custo, se paga sozinha no cartão);
#   as chaves de API ficam nas variáveis de ambiente (BILLING_*), como pede o doc. 05.
# - A despesa importada aponta a conexão e o id da cobrança no fornecedor, para a rotina diária
#   atualizar em vez de duplicar.
# - O domínio guarda quando o vencimento foi conferido no RDAP.
class CreateBillingConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :billing_connections, id: :uuid do |t|
      t.references :supplier, type: :uuid, null: false, foreign_key: true
      t.references :company, type: :uuid, foreign_key: true
      t.string :provider, null: false
      t.string :name, null: false
      t.string :account_id
      t.string :cost_center
      t.boolean :auto_paid, null: false, default: true
      t.boolean :active, null: false, default: true
      t.datetime :last_synced_at
      t.text :last_error
      t.timestamps
      t.check_constraint "company_id IS NOT NULL OR cost_center IS NOT NULL", name: "billing_connections_cost_center_present"
    end

    add_reference :payables, :billing_connection, type: :uuid, index: false, foreign_key: { on_delete: :nullify }
    add_column :payables, :external_id, :string
    add_index :payables, %i[billing_connection_id external_id], unique: true, where: "billing_connection_id IS NOT NULL",
                                                                 name: "index_payables_once_per_billing_charge"

    add_column :domains, :rdap_checked_at, :datetime
  end
end
