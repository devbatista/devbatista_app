# Fatura ao cliente (docs/specs/faturas): agrupa receitas do mesmo cliente e vai por e-mail,
# WhatsApp ou link público, com Pix. Os itens guardam uma cópia de cada receita, para o documento
# emitido não mudar; receivables.invoice_id aponta a fatura ativa da receita.
#
# As chaves estrangeiras da nota fiscal mantiveram o nome de quando a tabela era invoices
# (RenameInvoicesToFiscalInvoices); o nome gerado para receivables.invoice_id colidiria com o de
# receivables.fiscal_invoice_id. Primeiro elas passam ao nome que o Rails daria às colunas atuais.
class CreateInvoicesAndItems < ActiveRecord::Migration[8.1]
  OLD_FOREIGN_KEYS = [ %w[receivables invoice_id fiscal_invoice_id], %w[fiscal_invoices company_id company_id] ].freeze

  def change
    reversible do |dir|
      OLD_FOREIGN_KEYS.each do |table, old_column, new_column|
        old_name = fk_name(old_column == "company_id" ? "invoices" : table, old_column)
        new_name = fk_name(table, new_column)
        dir.up { execute "ALTER TABLE #{table} RENAME CONSTRAINT #{old_name} TO #{new_name}" }
        dir.down { execute "ALTER TABLE #{table} RENAME CONSTRAINT #{new_name} TO #{old_name}" }
      end
    end

    create_table :invoices, id: :uuid do |t|
      t.references :company, type: :uuid, null: false, foreign_key: true
      t.references :contact, type: :uuid, foreign_key: true
      t.integer :year
      t.integer :number
      t.string :status, null: false, default: "draft"
      t.date :due_on, null: false
      t.date :issued_on
      t.date :paid_on
      t.datetime :sent_at
      t.datetime :viewed_at
      t.integer :total_cents, null: false, default: 0
      t.text :client_notes
      t.text :notes
      t.string :cancellation_reason
      t.timestamps
    end
    add_index :invoices, %i[year number], unique: true, where: "number IS NOT NULL"
    add_index :invoices, :status
    add_index :invoices, :due_on

    create_table :invoice_items, id: :uuid do |t|
      t.references :invoice, type: :uuid, null: false, foreign_key: true
      t.references :receivable, type: :uuid, null: false, foreign_key: true
      t.string :description, null: false
      t.date :competence, null: false
      t.integer :amount_cents, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :invoice_items, %i[invoice_id receivable_id], unique: true

    add_reference :receivables, :invoice, type: :uuid, foreign_key: true
  end

  private

  # Mesmo cálculo do Rails (ActiveRecord::ConnectionAdapters::ForeignKeyDefinition).
  def fk_name(table, column)
    "fk_rails_#{OpenSSL::Digest::SHA256.hexdigest("#{table}_#{column}_fk").first(10)}"
  end
end
