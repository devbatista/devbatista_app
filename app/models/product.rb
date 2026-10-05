# Produto próprio da DevBatista (RF 35), acompanhado como unidade de negócio.
# MRR e clientes vêm das assinaturas ativas; o custo mensal é registrado mês a mês.
# Margem = (MRR − custo mensal) ÷ MRR.
class Product < ApplicationRecord
  include Auditable
  include LabeledEnums

  audited area: "produtos"
  labeled_enum :status, idea: "Ideia", development: "Em desenvolvimento", operating: "Em operação", discontinued: "Descontinuado"

  has_many :subscriptions, dependent: :restrict_with_error
  has_many :costs, -> { order(:month) }, class_name: "ProductCost", dependent: :destroy, inverse_of: :product

  validates :name, presence: true, uniqueness: { message: "já cadastrado" }

  scope :by_name, -> { order(:name) }

  def mrr_cents(on = Date.current)
    subscriptions.to_a.select { |s| s.counts_on?(on) }.sum(&:monthly_value_cents)
  end

  def clients_count(on = Date.current)
    subscriptions.to_a.count { |s| s.counts_on?(on) }
  end

  # Custo do mês (o último registrado até o mês pedido).
  def monthly_cost_cents(on = Date.current)
    costs.to_a.select { |c| c.month <= on.beginning_of_month }.last&.amount_cents.to_i
  end

  # Custo mensal no formulário: grava o custo do mês corrente.
  def monthly_cost
    monthly_cost_cents / 100.0
  end

  def monthly_cost=(value)
    @monthly_cost_cents = MoneyAttributes.to_cents(value)
  end

  def margin_percent(on = Date.current)
    mrr = mrr_cents(on)
    ((mrr - monthly_cost_cents(on)) * 100.0 / mrr).round(1) if mrr.positive?
  end

  def initials
    words = name.to_s.split
    (words.size > 1 ? words.first(2).map { |w| w[0] }.join : name.to_s[0, 2]).upcase
  end

  def url_href
    url.to_s.match?(%r{\Ahttps?://}i) ? url : "https://#{url}" if url.present?
  end

  def activity_name
    "o produto #{name}"
  end

  def to_s
    name
  end

  after_save :store_monthly_cost

  private

  def store_monthly_cost
    return if @monthly_cost_cents.nil?

    cost = costs.find_or_initialize_by(month: Date.current.beginning_of_month)
    cost.update!(amount_cents: @monthly_cost_cents) if cost.new_record? || cost.amount_cents != @monthly_cost_cents
    @monthly_cost_cents = nil
    costs.reset
  end
end
