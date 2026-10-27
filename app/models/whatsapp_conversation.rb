# Conversa de uma conta do WhatsApp com uma pessoa (docs/specs/whatsapp). A pessoa é
# identificada pelo BSUID (business-scoped user ID) da Meta; o telefone (wa_id) e o @usuário
# podem não vir. Pode estar ligada a um lead ou a um contato, nunca aos dois.
#
# Janela de 24h: mensagem livre só até 24h depois da última mensagem recebida da pessoa.
# Mensagens enviadas pelo app do celular não abrem nem estendem a janela.
class WhatsappConversation < ApplicationRecord
  WINDOW = 24.hours

  belongs_to :account, class_name: "WhatsappAccount", foreign_key: :whatsapp_account_id, inverse_of: :conversations
  belongs_to :lead, optional: true
  belongs_to :contact, optional: true
  has_many :messages, -> { order(:sent_at, :created_at) }, class_name: "WhatsappMessage",
                                                          foreign_key: :whatsapp_conversation_id, inverse_of: :conversation, dependent: :destroy

  normalizes :wa_id, with: ->(value) { value.to_s.gsub(/\D/, "").presence }
  normalizes :bsuid, :parent_bsuid, :username, :profile_name, with: ->(value) { value.to_s.strip.presence }

  validates :unread_count, numericality: { greater_than_or_equal_to: 0 }
  validates :bsuid, uniqueness: { scope: :whatsapp_account_id }, allow_nil: true
  validates :wa_id, uniqueness: { scope: :whatsapp_account_id }, allow_nil: true
  validate :identified
  validate :single_link

  scope :recent, -> { order(Arel.sql("last_message_at DESC NULLS LAST"), created_at: :desc) }
  scope :unread, -> { where(unread_count: 1..) }
  scope :unlinked, -> { where(lead_id: nil, contact_id: nil) }
  scope :window_open, -> { where(last_inbound_at: WINDOW.ago..) }

  def window_open?(at = Time.current)
    last_inbound_at.present? && last_inbound_at > at - WINDOW
  end

  def window_closes_at
    last_inbound_at && last_inbound_at + WINDOW
  end

  def link
    lead || contact
  end

  def linked?
    lead_id.present? || contact_id.present?
  end

  # Destinatário na Cloud API: o telefone quando a conversa tem (a Meta continua mandando o
  # telefone nos webhooks de quem recebe por ele); senão, o BSUID. Com os dois, `to` vence.
  def recipient_params
    wa_id ? { to: wa_id } : { recipient: bsuid }
  end

  def display_name
    profile_name || link&.name || username || (wa_id && "+#{wa_id}") || bsuid
  end

  def to_s
    display_name
  end

  private

  def identified
    errors.add(:base, "Informe o ID do WhatsApp (BSUID) ou o telefone") if bsuid.blank? && wa_id.blank?
  end

  def single_link
    errors.add(:base, "A conversa liga a um lead ou a um contato, não aos dois") if lead_id.present? && contact_id.present?
  end
end
