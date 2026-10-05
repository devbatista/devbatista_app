# Cotações de câmbio (PTAX de venda do Banco Central) guardadas por dia, para converter
# despesas em moeda estrangeira e manter o histórico usado em cada pagamento.
class CreateExchangeRates < ActiveRecord::Migration[8.1]
  def change
    create_table :exchange_rates do |t|
      t.string :currency, null: false
      t.date :quoted_on, null: false
      t.decimal :rate, precision: 12, scale: 6, null: false
      t.string :source, null: false, default: "ptax"
      t.timestamps
    end
    add_index :exchange_rates, [ :currency, :quoted_on ], unique: true
  end
end
