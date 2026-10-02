# Converte um lead qualificado em empresa, contato e oportunidade sem redigitar dados (RF 8).
# Se já existe empresa com o mesmo CNPJ, avisa e permite vincular a ela.
class LeadConversion
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :company_id, :integer          # empresa existente (opcional)
  attribute :trade_name, :string
  attribute :legal_name, :string
  attribute :cnpj, :string
  attribute :contact_name, :string
  attribute :contact_position, :string
  attribute :contact_whatsapp, :string
  attribute :contact_email, :string
  attribute :contact_primary, :boolean, default: true
  attribute :title, :string
  attribute :service_id, :integer
  attribute :estimated_value, :string
  attribute :probability, :integer
  attribute :expected_close_on, :date
  attribute :stage, :string, default: "meeting"
  attribute :user_id, :integer

  attr_reader :lead, :opportunity, :company

  validates :contact_name, :title, :user_id, presence: true
  validates :trade_name, :cnpj, presence: true, unless: :company_id?
  validates :stage, inclusion: { in: Opportunity::OPEN_STAGES }

  def self.from(lead)
    new(lead: lead, trade_name: lead.company_name, legal_name: lead.company_name, contact_name: lead.name,
        contact_whatsapp: lead.whatsapp, contact_email: lead.email, title: lead.service&.name || lead.company_name,
        service_id: lead.service_id, estimated_value: lead.service&.default_price&.to_s,
        probability: Opportunity::STAGE_PROBABILITY["meeting"], expected_close_on: Date.current + 30, user_id: lead.user_id)
  end

  def initialize(lead:, **attributes)
    @lead = lead
    super(**attributes)
  end

  def company_id? = company_id.present?

  # Empresa já cadastrada com o mesmo CNPJ, para o aviso na tela.
  def existing_company
    digits = cnpj.to_s.gsub(/\D/, "")
    Company.find_by(cnpj: digits) if digits.size == 14
  end

  def save
    return false unless valid? && lead.open?

    ActiveRecord::Base.transaction do
      @company = company_id? ? Company.find(company_id) : existing_company || create_company!
      contact = @company.contacts.create!(name: contact_name, position: contact_position, whatsapp: contact_whatsapp,
                                          email: contact_email, phone: lead.phone, primary: contact_primary || @company.primary_contact.nil?)
      @opportunity = Opportunity.create!(title: title, lead: lead, company: @company, service_id: service_id, user_id: user_id,
                                         stage: stage, estimated_value: estimated_value, probability: probability,
                                         expected_close_on: expected_close_on, notes: lead.notes)
      lead.update!(status: "converted", company: @company, converted_at: Time.current)
      contact
    end
    true
  rescue ActiveRecord::RecordInvalid => e
    e.record.errors.each { |error| errors.add(:base, "#{e.record.class.model_name.human}: #{error.full_message}") }
    false
  end

  private

  def create_company!
    Company.create!(trade_name: trade_name, legal_name: legal_name.presence || trade_name, cnpj: cnpj, status: "prospect",
                    email: contact_email, phone: lead.phone)
  end
end
