# Aplicação de um cliente (RF 29): sistema, site ou app, com ambiente, URL, tecnologia,
# repositório e hospedagem (um servidor ou um serviço externo). Na spec é "Application".
class App < ApplicationRecord
  include Inventory

  HOSTING_TYPES = %w[Server ExternalService].freeze

  environment_field
  labeled_enum :status, active: "Ativa", maintenance: "Em manutenção", disabled: "Desativada"

  belongs_to :company
  belongs_to :hosting, polymorphic: true, optional: true
  belongs_to :project, optional: true
  belongs_to :contract, optional: true
  belongs_to :user, optional: true
  has_many :databases, dependent: :destroy
  has_many :integrations, dependent: :destroy
  has_many :external_services, dependent: :nullify
  has_many :tickets, dependent: :nullify

  validates :name, presence: true
  validates :hosting_type, inclusion: { in: HOSTING_TYPES }, allow_nil: true
  validates :url, :repository_url, format: { with: %r{\A(https?://)?[^\s/]+\.[^\s]+\z}i, message: "não parece um endereço válido" }, allow_blank: true
  validate :links_from_same_company

  normalizes :hosting_type, with: ->(value) { value.presence }

  scope :by_name, -> { order(:name) }
  scope :search, lambda { |term|
    q = "%#{sanitize_sql_like(term.to_s.strip)}%"
    where("unaccent(apps.name) ILIKE unaccent(:q) OR apps.url ILIKE :q OR unaccent(apps.tech_stack) ILIKE unaccent(:q)", q: q)
  }

  # Hospedagem no select: "Server:12" ou "ExternalService:3".
  def hosting_key
    "#{hosting_type}:#{hosting_id}" if hosting_id
  end

  def hosting_key=(value)
    type, id = value.to_s.split(":", 2)
    self.hosting_type = type.presence_in(HOSTING_TYPES)
    self.hosting_id = hosting_type && id.to_i
  end

  def host_name
    url.to_s.sub(%r{\Ahttps?://}i, "").split("/").first if url.present?
  end

  def url_href
    url.to_s.match?(%r{\Ahttps?://}i) ? url : "https://#{url}" if url.present?
  end

  def repository_href
    repository_url.to_s.match?(%r{\Ahttps?://}i) ? repository_url : "https://#{repository_url}" if repository_url.present?
  end

  # Domínio do cliente que atende o endereço da aplicação.
  def domain
    host = host_name.to_s.downcase
    company.domains.to_a.select { |d| host == d.name || host.end_with?(".#{d.name}") }.max_by { |d| d.name.size } if host.present?
  end

  # Custo mensal em reais pago pela DevBatista: hospedagem e serviços externos da aplicação.
  def monthly_cost_cents
    items = [ (hosting.monthly_cost_cents if hosting.is_a?(Server)) ]
    items += (external_services.to_a | [ (hosting if hosting.is_a?(ExternalService)) ].compact).select(&:paid_by_devbatista?).map(&:monthly_brl_cents)
    items.compact.sum
  end

  def activity_name
    "a aplicação #{name}"
  end

  def to_s
    name
  end

  private

  def links_from_same_company
    errors.add(:project, "é de outro cliente") if project && project.company_id != company_id
    errors.add(:contract, "é de outro cliente") if contract && contract.company_id != company_id
  end
end
