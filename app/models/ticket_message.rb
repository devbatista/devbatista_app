# Mensagem no histórico do chamado: resposta ao cliente, nota interna (só a equipe vê) ou
# mensagem do cliente registrada pela equipe (telefone, e-mail, WhatsApp).
class TicketMessage < ApplicationRecord
  include Auditable
  include LabeledEnums

  CHANNELS = %w[Telefone E-mail WhatsApp Reunião].freeze

  audited area: "suporte"
  labeled_enum :kind, reply: "Resposta ao cliente", note: "Nota interna", client: "Mensagem do cliente"

  belongs_to :ticket, inverse_of: :messages
  belongs_to :user
  belongs_to :contact, optional: true

  validates :body, presence: true
  validates :channel, inclusion: { in: CHANNELS }, allow_blank: true
  validate :contact_from_ticket_company

  before_validation { self.contact ||= ticket&.contact if client? }

  def author_name
    client? ? (contact&.name || "Cliente") : user.name
  end

  def activity_name
    "#{{ 'reply' => 'uma resposta', 'note' => 'uma nota interna', 'client' => 'uma mensagem do cliente' }[kind]} no chamado #{ticket.code}"
  end

  def activity_company
    ticket.company
  end

  def to_s
    "#{kind_label} · #{ticket.code}"
  end

  private

  def contact_from_ticket_company
    errors.add(:contact, "não é da empresa do chamado") if contact && ticket && contact.company_id != ticket.company_id
  end

  def activity_description(action, changes)
    return super unless action == "create"

    reply? ? "Respondeu o chamado #{ticket.code}" : "Registrou #{activity_name}"
  end
end
