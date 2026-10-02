# Item da proposta: um serviço do catálogo com o valor proposto (o preço padrão vem do
# catálogo e pode ser alterado).
class ProposalItem < ApplicationRecord
  include LabeledEnums
  include MoneyAttributes

  labeled_enum :recurrence, monthly: "Mensal", quarterly: "Trimestral", semiannual: "Semestral", annual: "Anual", one_off: "Avulsa"
  money_attribute :price, :default_price

  belongs_to :proposal
  belongs_to :service

  validates :price_cents, numericality: { greater_than_or_equal_to: 0 }

  before_validation :defaults_from_service, if: -> { service && (new_record? || will_save_change_to_service_id?) }

  def mrr_cents
    CustomerService.mrr_for(price_cents, recurrence)
  end

  private

  def defaults_from_service
    self.default_price_cents = service.default_price_cents if default_price_cents.to_i.zero? || will_save_change_to_service_id?
    self.price_cents = service.default_price_cents if price_cents.to_i.zero?
    self.recurrence = service.recurring? ? "monthly" : "one_off" if recurrence.blank? || (new_record? && recurrence == "monthly" && !service.recurring?)
  end
end
