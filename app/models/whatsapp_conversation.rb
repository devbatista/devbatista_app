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
  normalizes :bsuid, :parent_bsuid, :username, :profile_name, :saved_name, with: ->(value) { value.to_s.strip.presence }

  validates :unread_count, numericality: { greater_than_or_equal_to: 0 }
  validates :bsuid, uniqueness: { scope: :whatsapp_account_id }, allow_nil: true
  validates :wa_id, uniqueness: { scope: :whatsapp_account_id }, allow_nil: true
  validate :identified
  validate :single_link

  scope :recent, -> { order(Arel.sql("last_message_at DESC NULLS LAST"), created_at: :desc) }
  scope :unread, -> { where(unread_count: 1..) }
  scope :unlinked, -> { where(lead_id: nil, contact_id: nil) }
  scope :window_open, -> { where(last_inbound_at: WINDOW.ago..) }
  # A sincronização da agenda do celular cria conversas ainda sem mensagem; a caixa de entrada só mostra as outras.
  scope :with_messages, -> { where.not(last_message_at: nil) }

  # Acha ou cria a conversa da pessoa que veio num webhook, pelo BSUID e pelo telefone, e
  # completa o que faltar. O BSUID é a identidade; o telefone pode passar a outra pessoa:
  # - a conversa achada só pelo telefone e sem BSUID é da mesma pessoa e é juntada a esta;
  # - com outro BSUID, o telefone sai dela (o número mudou de dono);
  # - previous_bsuid e previous_wa_id (mensagens de sistema de troca de BSUID e de número) apontam
  #   a conversa antiga da pessoa, que fica com os dados novos.
  # Dois webhooks criando a mesma conversa ao mesmo tempo: o segundo esbarra no índice único e
  # tenta de novo, achando a que o primeiro criou.
  def self.locate!(account, bsuid: nil, wa_id: nil, previous_bsuid: nil, previous_wa_id: nil, **attributes)
    bsuid = normalize_value_for(:bsuid, bsuid)
    wa_id = normalize_value_for(:wa_id, wa_id)
    raise ArgumentError, "informe o BSUID ou o telefone" unless bsuid || wa_id

    attempts = 0
    begin
      transaction(requires_new: true) do
        scope = account.conversations
        same = [ (scope.find_by(bsuid: previous_bsuid) if previous_bsuid.present?),
                 (scope.find_by(wa_id: normalize_value_for(:wa_id, previous_wa_id)) if previous_wa_id.present?),
                 (scope.find_by(bsuid: bsuid) if bsuid) ].compact.uniq
        by_phone = wa_id && scope.find_by(wa_id: wa_id)
        if by_phone && same.exclude?(by_phone)
          if by_phone.bsuid.nil? || bsuid.nil?
            same << by_phone
          else
            by_phone.update!(wa_id: nil)
          end
        end

        conversation = same.shift || scope.new
        same.each { |other| conversation.absorb!(other) }
        conversation.assign_attributes({ bsuid: bsuid, wa_id: wa_id }.compact.merge(attributes.compact))
        conversation.save!
        conversation
      end
    rescue ActiveRecord::RecordNotUnique
      (attempts += 1) < 3 ? retry : raise
    end
  end

  # Junta nesta a outra conversa da mesma pessoa: mensagens, vínculo, não lidas, datas e nomes.
  # A outra é apagada antes de esta herdar o BSUID ou o telefone dela (índices únicos).
  def absorb!(other)
    other.messages.update_all(whatsapp_conversation_id: id)
    self.lead_id, self.contact_id = other.lead_id, other.contact_id unless linked?
    self.unread_count += other.unread_count
    self.last_inbound_at = [ last_inbound_at, other.last_inbound_at ].compact.max
    if other.last_message_at && (last_message_at.nil? || other.last_message_at > last_message_at)
      self.last_message_at, self.preview = other.last_message_at, other.preview
    end
    inherited = other.slice(:bsuid, :wa_id, :parent_bsuid, :username, :profile_name, :saved_name)
    other.destroy!
    inherited.each { |attribute, value| self[attribute] ||= value }
  end

  # Atualiza a conversa com uma mensagem que acabou de entrar:
  # - prévia e data da última mensagem, se ela for a mais nova (reações e avisos de sistema não contam);
  # - recebida do contato, fora do histórico: abre a janela de 24h e soma às não lidas;
  # - enviada pelo celular: zera as não lidas (quem respondeu no app já leu), sem mexer na janela.
  def record_message!(message)
    with_lock do
      unless message.kind_reaction? || message.kind_system?
        if last_message_at.nil? || message.sent_at >= last_message_at
          self.last_message_at = message.sent_at
          self.preview = message.preview_text
        end
        if message.inbound? && !message.from_history?
          self.last_inbound_at = [ last_inbound_at, message.sent_at ].compact.max
          self.unread_count += 1
        elsif message.origin_phone? && !message.from_history?
          self.unread_count = 0
        end
      end
      save!
    end
  end

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

  # O nome salvo na agenda do celular vem antes do nome do perfil, que a própria pessoa escolhe.
  def display_name
    saved_name || profile_name || link&.name || username || (wa_id && "+#{wa_id}") || bsuid
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
