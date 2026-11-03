# Conexão de cobrança: um fornecedor cujas faturas a DevBatista puxa pela API (AWS, Cloudflare, Railway)
# e lança em Despesas, sem digitar. A rotina diária (BillingSyncJob) cria ou atualiza uma despesa
# por cobrança, pelo id da cobrança no fornecedor (Payable#external_id).
#
# As chaves de API não ficam no banco (doc. 05): vêm das variáveis de ambiente listadas em
# PROVIDERS. A conexão guarda só a conta, o centro de custo e se a cobrança é automática no
# cartão — nesse caso a despesa é marcada como paga no vencimento, já que o fornecedor não diz
# se a fatura do cartão foi paga.
class BillingConnection < ApplicationRecord
  include Auditable
  include LabeledEnums
  include CostCenter

  PROVIDERS = {
    "aws" => { client: "Billing::Aws", env: %w[BILLING_AWS_ACCESS_KEY_ID BILLING_AWS_SECRET_ACCESS_KEY],
               account_label: "ID da conta AWS (12 dígitos)" },
    "cloudflare" => { client: "Billing::Cloudflare", env: %w[BILLING_CLOUDFLARE_API_TOKEN],
                      account_label: "Account ID da Cloudflare" },
    "railway" => { client: "Billing::Railway", env: %w[BILLING_RAILWAY_API_TOKEN],
                   account_label: "ID do workspace do Railway" }
  }.freeze

  audited area: "financeiro", ignore: %w[last_synced_at last_error]
  labeled_enum :provider, aws: "AWS", cloudflare: "Cloudflare", railway: "Railway"

  belongs_to :supplier
  has_many :payables, dependent: :nullify

  normalizes :account_id, with: ->(value) { value.to_s.strip.presence }

  validates :name, :account_id, presence: true
  validates :account_id, format: { with: /\A\d{12}\z/, message: "precisa ter os 12 dígitos da conta" }, if: :aws?
  validates :account_id, format: { with: /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/, message: "precisa ser o ID do workspace (UUID)" },
                         if: :railway?
  validates :account_id, uniqueness: { scope: :provider, message: "já tem uma conexão" }

  scope :active, -> { where(active: true) }
  scope :by_name, -> { order(:name) }

  # Variáveis de ambiente com as chaves da API que ainda não foram configuradas.
  def missing_env(env = ENV)
    PROVIDERS.fetch(provider)[:env].select { |key| env[key].blank? }
  end

  def configured?(env = ENV) = missing_env(env).empty?

  def client
    PROVIDERS.fetch(provider)[:client].constantize.new(self)
  end

  def failing? = last_error.present?

  def activity_name
    "a conexão de cobrança #{name}"
  end

  def to_s
    name
  end
end
