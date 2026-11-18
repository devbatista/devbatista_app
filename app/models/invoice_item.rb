# Linha da fatura: cópia da receita cobrada (descrição, competência e valor) no momento em que
# entrou na fatura, para o documento emitido não mudar se a receita for editada.
class InvoiceItem < ApplicationRecord
  belongs_to :invoice, inverse_of: :items
  belongs_to :receivable

  validates :description, :competence, presence: true
  validates :amount_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :receivable_from_invoice_company

  def competence_label
    I18n.l(competence, format: "%B/%Y").capitalize if competence
  end

  private

  def receivable_from_invoice_company
    errors.add(:receivable, "é de outro cliente") if receivable && invoice && receivable.company_id != invoice.company_id
  end
end
