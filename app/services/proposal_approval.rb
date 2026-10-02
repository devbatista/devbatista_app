# Fecha o negócio a partir de uma proposta aprovada (RF 11): cria o contrato e os serviços
# contratados com os dados da proposta, passa a empresa para Ativo e a oportunidade para Fechado.
class ProposalApproval
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :approved_on, :date, default: -> { Date.current }
  attribute :start_date, :date, default: -> { Date.current }
  attribute :end_date, :date
  attribute :due_day, :integer, default: 10
  attribute :renewal, :string, default: "manual"

  attr_reader :proposal, :contract

  validates :approved_on, :start_date, :end_date, presence: true
  validates :due_day, numericality: { only_integer: true, in: 1..31 }, allow_nil: true
  validates :renewal, inclusion: { in: Contract.renewals.keys }
  validate :proposal_can_be_approved

  def initialize(proposal:, **attributes)
    @proposal = proposal
    super(**attributes)
    self.end_date ||= start_date && (start_date + 1.year - 1.day)
  end

  def save
    return false unless valid?

    ActiveRecord::Base.transaction do
      company = proposal.company
      @contract = Contract.create!(company: company, title: proposal.title, status: "active", start_date: start_date,
                                   end_date: end_date, renewal: renewal, periodicity: periodicity, value_cents: contract_value_cents,
                                   notes: [ "Gerado da proposta #{proposal.code}.", proposal.payment_terms ].compact_blank.join(" "))
      proposal.items.each do |item|
        CustomerService.create!(company: company, service: item.service, contract: @contract, price_cents: item.price_cents,
                                recurrence: item.recurrence, start_date: start_date, due_day: due_day,
                                description: item.description, status: "active")
      end
      proposal.update!(status: "approved", decided_on: approved_on, contract: @contract)
      company.update!(status: "active") unless company.active?
      proposal.opportunity&.update!(stage: "won", closed_on: approved_on)
    end
    true
  rescue ActiveRecord::RecordInvalid => e
    errors.add(:base, e.record.errors.full_messages.to_sentence)
    false
  end

  # Contrato mensal com a soma do MRR dos itens recorrentes; se só há avulsos, valor único.
  def periodicity
    proposal.items.any? { |i| !i.one_off? } ? "monthly" : "one_time"
  end

  def contract_value_cents
    periodicity == "monthly" ? proposal.items.sum(&:mrr_cents) : proposal.total_cents
  end

  private

  def proposal_can_be_approved
    errors.add(:base, "Só proposta Enviada ou Visualizada pode ser aprovada") unless proposal.sent? || proposal.viewed?
    errors.add(:base, "Converta o lead em cliente antes de aprovar") if proposal.company.nil?
    errors.add(:base, "A proposta não tem serviços") if proposal.items.empty?
    errors.add(:end_date, "precisa ser depois do início") if start_date && end_date && end_date <= start_date
  end
end
