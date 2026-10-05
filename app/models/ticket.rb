# Chamado de suporte (RF 21). Número sequencial gerado pelo banco e data de abertura
# automática; a data de conclusão é registrada ao Resolver. Prioridade Crítica notifica a
# equipe na hora, sem esperar a rotina diária. No MVP só a equipe abre chamados.
class Ticket < ApplicationRecord
  include Auditable
  include LabeledEnums

  FLOW = %w[open analyzing in_progress waiting_client resolved closed].freeze
  OPEN_STATUSES = %w[open analyzing in_progress waiting_client].freeze

  audited area: "suporte"
  labeled_enum :status, { open: "Aberto", analyzing: "Em análise", in_progress: "Em atendimento",
                          waiting_client: "Aguardando cliente", resolved: "Resolvido", closed: "Fechado" }, prefix: :status
  labeled_enum :category, bug: "Erro", question: "Dúvida", improvement: "Melhoria", infrastructure: "Infraestrutura", access: "Acesso"
  labeled_enum :priority, low: "Baixa", normal: "Normal", high: "Alta", critical: "Crítica"

  belongs_to :company
  belongs_to :contact, optional: true
  belongs_to :user, optional: true
  belongs_to :app, optional: true
  has_many :messages, -> { order(:created_at, :id) }, class_name: "TicketMessage", dependent: :destroy, inverse_of: :ticket
  has_many :time_entries, dependent: :nullify

  validates :subject, :description, :category, presence: true
  validate :contact_from_company
  validate :app_from_company

  before_validation :suggest_contact
  before_validation { self.opened_at ||= Time.current }
  before_save :track_resolution
  after_save :notify_critical, if: -> { saved_change_to_priority? && critical? && open? }

  scope :open, -> { where(status: OPEN_STATUSES) }
  scope :search, lambda { |term|
    number = term.to_s.delete("#").strip
    clause = "unaccent(tickets.subject) ILIKE unaccent(:q)"
    clause += " OR tickets.number = :number" if number.match?(/\A\d+\z/)
    where(clause, q: "%#{sanitize_sql_like(term.to_s.strip)}%", number: number.to_i)
  }

  def open? = status.in?(OPEN_STATUSES)

  def code
    "##{number}" if number
  end

  def resolution_minutes
    ((resolved_at - opened_at) / 60).round if resolved_at
  end

  def activity_name
    "o chamado #{code} (#{subject})"
  end

  def to_s
    "#{code} — #{subject}"
  end

  private

  # O contato principal da empresa é sugerido por padrão (RF 13).
  def suggest_contact
    self.contact ||= company&.primary_contact
  end

  # Resolvido ou Fechado guarda a conclusão; voltar para um status em aberto a apaga.
  def track_resolution
    return unless will_save_change_to_status?

    if open?
      self.resolved_at = nil
    else
      self.resolved_at ||= Time.current
    end
  end

  def notify_critical
    created = previously_new_record?
    Notification.deliver!(
      kind: "ticket_critical", level: "crit", notifiable: self, dedup_key: "ticket-#{id}-critical",
      title: created ? "Chamado crítico #{code} aberto para #{company.trade_name}: #{subject}" : "Chamado #{code} de #{company.trade_name} passou para prioridade Crítica: #{subject}",
      path: Rails.application.routes.url_helpers.ticket_path(self)
    )
  end

  def app_from_company
    errors.add(:app, "é de outro cliente") if app && app.company_id != company_id
  end

  def contact_from_company
    errors.add(:contact, "não é da empresa do chamado") if contact && contact.company_id != company_id
  end
end
