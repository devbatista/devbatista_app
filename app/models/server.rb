# Servidor (RF 30). O custo mensal entra no custo direto do cliente.
class Server < ApplicationRecord
  include Inventory
  include MoneyAttributes

  environment_field
  money_attribute :monthly_cost

  belongs_to :company
  belongs_to :supplier
  has_many :apps, as: :hosting, dependent: :nullify

  validates :name, presence: true, uniqueness: { message: "já cadastrado" }
  validates :host, presence: true
  validates :monthly_cost_cents, numericality: { greater_than_or_equal_to: 0 }

  scope :by_name, -> { order(:name) }
  scope :search, ->(term) { where("servers.name ILIKE :q OR servers.host ILIKE :q", q: "%#{sanitize_sql_like(term.to_s.strip)}%") }

  def hosting_label = "#{name} · #{supplier&.name}"

  def activity_name
    "o servidor #{name}"
  end

  def to_s
    name
  end
end
