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

  MEDIA_KINDS = %w[image audio video document sticker].freeze
  # Anexos que o Admin envia (tipos aceitos pela Cloud API). Figurinha não.
  UPLOAD_TYPES = {
    "image" => %w[image/jpeg image/png],
    "audio" => %w[audio/aac audio/mp4 audio/mpeg audio/amr audio/ogg],
    "video" => %w[video/mp4 video/3gpp],
    "document" => %w[application/pdf text/plain application/msword application/vnd.openxmlformats-officedocument.wordprocessingml.document
                     application/vnd.ms-excel application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
                     application/vnd.ms-powerpoint application/vnd.openxmlformats-officedocument.presentationml.presentation]
  }.freeze
  TEXT_LIMIT = 4096

  # Linha do tempo da conversa: tudo menos as reações, que vão sobre a mensagem reagida.
  scope :timeline, -> { where.not(kind: "reaction") }
  # Paginação por cursor da linha do tempo: as anteriores a `message`, sem pular nem repetir.
  scope :before_cursor, ->(message) { where("(whatsapp_messages.sent_at, whatsapp_messages.id) < (?, ?)", message.sent_at, message.id) }
  scope :chronological, -> { order(:sent_at, :id) }

  after_create_commit :broadcast_created
  after_update_commit :broadcast_changed
  after_destroy_commit :broadcast_reacted_message, if: :kind_reaction?

  def self.upload_kind(mime_type)
    UPLOAD_TYPES.find { |_kind, types| types.include?(mime_type.to_s) }&.first
  end

  validates :sent_at, presence: true
  validates :wa_message_id, uniqueness: true, allow_nil: true
  validates :template_name, :template_language, presence: true, if: :kind_template?
  validates :reaction_to_wa_message_id, presence: true, if: :kind_reaction?
  validate :origin_matches_direction

  # Texto da prévia na lista de conversas: o corpo ou a legenda, ou o tipo da mensagem.
  def preview_text
    (body.to_s.squish.presence || kind_label).truncate(120)
  end

  def media?
    MEDIA_KINDS.include?(kind)
  end

  # Primeira mensagem do dia na conversa: leva o separador de dia na linha do tempo.
  def first_of_day?
    previous = conversation.messages.timeline.before_cursor(self).reorder(sent_at: :desc, id: :desc).pick(:sent_at)
    previous.nil? || previous.to_date != sent_at.to_date
  end

  # Reações a mostrar: a mais nova de cada lado; emoji vazio é reação removida.
  def visible_reactions
    reactions.reject { |reaction| reaction.reaction_emoji.blank? }
  end

  # Falhou no envio pelo Admin: pode ser enviada de novo, como mensagem nova.
  def retryable?
    status_failed? && origin_admin?
  end

  def fail_send!(message, code: nil)
    update!(status: "failed", error_code: code&.to_s, error_message: message.to_s.truncate(500))
  end

  def template_values
    params = template_params.is_a?(Hash) ? template_params : { "body" => Array(template_params) }
    { "body" => Array(params["body"]), "header" => Array(params["header"]), "buttons" => params["buttons"].to_h }
  end

  # Redesenha na conversa aberta (status, edição, exclusão, mídia que terminou de baixar).
  def broadcast_message_later
    broadcast_replace_later_to conversation, :whatsapp, target: ActionView::RecordIdentifier.dom_id(self), partial: "whatsapp_messages/message",
                                                        locals: { message: self }
  end

  private

  def broadcast_created
    return broadcast_reacted_message if kind_reaction?

    broadcast_append_later_to conversation, :whatsapp, target: ActionView::RecordIdentifier.dom_id(conversation, :thread),
                                                       partial: "whatsapp_messages/message", locals: { message: self }
  end

  def broadcast_changed
    kind_reaction? ? broadcast_reacted_message : broadcast_message_later
  end

  def broadcast_reacted_message
    WhatsappMessage.find_by(wa_message_id: reaction_to_wa_message_id)&.broadcast_message_later
  end

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
