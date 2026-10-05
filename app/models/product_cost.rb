# Custo mensal de um produto próprio (infraestrutura e serviços), um registro por mês.
class ProductCost < ApplicationRecord
  belongs_to :product, inverse_of: :costs

  validates :month, presence: true, uniqueness: { scope: :product_id }
  validates :amount_cents, numericality: { greater_than_or_equal_to: 0 }

  before_validation { self.month = month&.beginning_of_month }
end
