# Catálogo de serviços: o que a DevBatista vende (RF 15).
class Service < ApplicationRecord
  include Auditable
  include LabeledEnums
  include MoneyAttributes

  CATEGORIES = [ "Consultoria", "Desenvolvimento", "Sustentação", "Infraestrutura", "Automação e IA", "Outros" ].freeze

  audited area: "administracao"
  labeled_enum :kind, recurring: "Recorrente", project: "Projeto", one_off: "Avulso"
  labeled_enum :status, active: "Ativo", inactive: "Inativo"
  money_attribute :default_price

  has_many :customer_services, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true
  validates :category, presence: true
  validates :default_price_cents, numericality: { greater_than_or_equal_to: 0 }

  scope :by_name, -> { order(:name) }
  # Serviço Inativo não aparece em novas propostas nem em novos serviços contratados.
  scope :available, -> { active.by_name }

  def activity_name
    "o serviço #{name}"
  end

  def to_s
    name
  end
end
