# Nota fiscal passa de Invoice para FiscalInvoice: "invoice" é a fatura que vai ao cliente antes
# do pagamento; a nota fiscal é emitida depois, na contabilidade, e só registrada aqui.
# Além da tabela e da coluna, troca o tipo guardado nas associações polimórficas (anexos,
# histórico, documentos, interações e notificações), o tipo de documento
# "invoice" e o caminho das notificações (/finance/invoices → /finance/fiscal-invoices).
# A trilha de auditoria é só inserção e fica como está: AuditLog::LEGACY_TYPES traduz o tipo antigo.
class RenameInvoicesToFiscalInvoices < ActiveRecord::Migration[8.1]
  POLYMORPHIC = {
    active_storage_attachments: :record_type, activities: :subject_type, documents: :documentable_type,
    interactions: :subject_type, notifications: :notifiable_type
  }.freeze

  def up
    rename_table :invoices, :fiscal_invoices
    rename_column :receivables, :invoice_id, :fiscal_invoice_id
    rename_values("Invoice", "FiscalInvoice", "invoice", "fiscal_invoice")
    rewrite_paths("/finance/invoices", "/finance/fiscal-invoices")
  end

  def down
    rewrite_paths("/finance/fiscal-invoices", "/finance/invoices")
    rename_values("FiscalInvoice", "Invoice", "fiscal_invoice", "invoice")
    rename_column :receivables, :fiscal_invoice_id, :invoice_id
    rename_table :fiscal_invoices, :invoices
  end

  private

  def rename_values(old_type, new_type, old_kind, new_kind)
    POLYMORPHIC.each do |table, column|
      execute "UPDATE #{table} SET #{column} = #{quote(new_type)} WHERE #{column} = #{quote(old_type)}"
    end
    execute "UPDATE documents SET kind = #{quote(new_kind)} WHERE kind = #{quote(old_kind)}"
  end

  # Só troca o segmento inteiro, como nas migrations de caminho anteriores.
  def rewrite_paths(old, new)
    execute <<~SQL
      UPDATE notifications
      SET path = #{quote(new)} || substr(path, #{old.length + 1})
      WHERE path = #{quote(old)} OR path LIKE #{quote("#{old}/%")} OR path LIKE #{quote("#{old}?%")}
    SQL
  end

  def quote(value)
    connection.quote(value)
  end
end
