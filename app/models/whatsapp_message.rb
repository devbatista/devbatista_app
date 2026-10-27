# Mensagem de uma conversa do WhatsApp (docs/specs/whatsapp). O wa_message_id da Meta é único
# e torna o processamento dos webhooks idempotente: a mesma mensagem nunca entra duas vezes.
#
# Origem: enviada pelo Admin, enviada pelo app do celular (eco da coexistência) ou recebida do
# contato. from_history marca as que vieram da sincronização do histórico (até 180 dias).
#
# Resposta citada: reply_to_wa_message_id aponta a mensagem citada (context.id do webhook).
# Reação (kind reaction): aparece sobre a mensagem reagida (reaction_to_wa_message_id), não como
# mensagem nova na conversa; reaction_emoji vazio é a pessoa removendo a reação.
class WhatsappMessage < ApplicationRecord
  include LabeledEnums

  labeled_enum :direction, inbound: "Recebida", outbound: "Enviada"
  labeled_enum :origin, { admin: "Admin", phone: "Celular", contact: "Contato" }, prefix: :origin
  labeled_enum :kind, {
    text: "Texto", image: "Imagem", audio: "Áudio", video: "Vídeo", document: "Documento", sticker: "Figurinha",
    location: "Localização", contacts: "Contato", interactive: "Resposta interativa", button: "Resposta de botão",
    reaction: "Reação", template: "Template", system: "Mensagem de sistema", unsupported: "Não suportada"
  }, prefix: :kind
  labeled_enum :status, {
    pending: "Enviando", sent: "Enviada", delivered: "Entregue", read: "Lida", failed: "Falhou", received: "Recebida"
  }, prefix: :status

  belongs_to :conversation, class_name: "WhatsappConversation", foreign_key: :whatsapp_conversation_id, inverse_of: :messages
  belongs_to :user, optional: true # autor, nas mensagens enviadas pelo Admin
  belongs_to :reply_to, class_name: "WhatsappMessage", primary_key: :wa_message_id,
                        foreign_key: :reply_to_wa_message_id, optional: true, inverse_of: false
  has_many :reactions, -> { kind_reaction.order(:sent_at, :created_at) }, class_name: "WhatsappMessage", primary_key: :wa_message_id,
                                                                          foreign_key: :reaction_to_wa_message_id, inverse_of: false
  has_one_attached :media

  # Linha do tempo da conversa: tudo menos as reações, que vão sobre a mensagem reagida.
  scope :timeline, -> { where.not(kind: "reaction") }

  validates :sent_at, presence: true
  validates :wa_message_id, uniqueness: true, allow_nil: true
  validates :template_name, :template_language, presence: true, if: :kind_template?
  validates :reaction_to_wa_message_id, presence: true, if: :kind_reaction?
  validate :origin_matches_direction

  private

  def origin_matches_direction
    return if direction.blank? || origin.blank? || status.blank?

    if inbound?
      errors.add(:origin, "de mensagem recebida é o contato") unless origin_contact?
      errors.add(:status, "de mensagem recebida é Recebida") unless status_received?
    else
      errors.add(:origin, "de mensagem enviada é o Admin ou o celular") if origin_contact?
      errors.add(:status, "Recebida só vale para mensagem recebida") if status_received?
    end
  end
end
