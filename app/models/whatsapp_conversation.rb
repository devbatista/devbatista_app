# Conversa de uma conta do WhatsApp com uma pessoa (docs/specs/whatsapp). A pessoa é
# identificada pelo BSUID (business-scoped user ID) da Meta; o telefone (wa_id) e o @usuário
# podem não vir. Pode estar ligada a um lead ou a um contato, nunca aos dois.
#
# Vínculo (Fase 7a): com telefone e sem vínculo, a conversa se liga sozinha ao único lead em aberto
# ou contato com o mesmo número (com e sem o nono dígito, Whatsapp::Phone). Com mais de um, os
# candidatos aparecem no painel. Desvinculada à mão, fica marcada (auto_link_blocked_at) e não se
# liga sozinha de novo até o telefone mudar. Ligada, cada dia de conversa vira a interação "WhatsApp" do lead
# ou da oportunidade (WhatsappInteractionJob).
#
# Janela de 24h: mensagem livre só até 24h depois da última mensagem recebida da pessoa.
# Mensagens enviadas pelo app do celular não abrem nem estendem a janela.
class WhatsappConversation < ApplicationRecord
  WINDOW = 24.hours
  # Filtros da caixa de entrada (docs/design/whatsapp/conversas.html).
  FILTERS = { "todas" => "Todas", "nao-lidas" => "Não lidas", "leads" => "Leads", "clientes" => "Clientes",
              "sem-vinculo" => "Sem vínculo", "janela" => "Janela aberta" }.freeze
  # Mudanças que redesenham o item da lista (as outras não aparecem nela).
  INBOX_ATTRIBUTES = %w[unread_count preview last_inbound_at saved_name profile_name username wa_id lead_id contact_id].freeze

  belongs_to :account, class_name: "WhatsappAccount", foreign_key: :whatsapp_account_id, inverse_of: :conversations
  belongs_to :lead, optional: true
  belongs_to :contact, optional: true
  belongs_to :linked_by, class_name: "User", optional: true
  has_many :interactions, dependent: nil # a chave estrangeira solta as interações (on delete set null)
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
  # Sem vínculo e sem a marca de desvinculada à mão: o vínculo automático pode ligar.
  scope :auto_linkable, -> { unlinked.where(auto_link_blocked_at: nil) }
  scope :window_open, -> { where(last_inbound_at: WINDOW.ago..) }
  # A sincronização da agenda do celular cria conversas ainda sem mensagem; a caixa de entrada só mostra as outras.
  scope :with_messages, -> { where.not(last_message_at: nil) }
  scope :inbox_order, -> { order(last_message_at: :desc, id: :desc) }
  # Paginação por cursor da caixa de entrada: as conversas depois de `conversation` na ordem da lista.
  scope :after_cursor, lambda { |conversation|
    where("(whatsapp_conversations.last_message_at, whatsapp_conversations.id) < (?, ?)", conversation.last_message_at, conversation.id)
  }
  # Nome do perfil, nome salvo na agenda, telefone (só os dígitos) e @usuário.
  scope :search, lambda { |term|
    names = where("unaccent(whatsapp_conversations.profile_name) ILIKE unaccent(:q) OR unaccent(whatsapp_conversations.saved_name) ILIKE unaccent(:q) " \
                  "OR unaccent(whatsapp_conversations.username) ILIKE unaccent(:q)", q: "%#{sanitize_sql_like(term.to_s.strip)}%")
    digits = term.to_s.gsub(/\D/, "")
    digits.length >= 3 ? names.or(where("whatsapp_conversations.wa_id LIKE ?", "%#{digits}%")) : names
  }

  before_save :phone_changed, if: -> { will_save_change_to_wa_id? && wa_id }
  after_commit :broadcast_inbox, on: %i[create update]
  after_commit :link_changed, on: %i[create update], if: -> { saved_change_to_lead_id? || saved_change_to_contact_id? }
  # Não lidas zeradas (conversa aberta ou resposta pelo celular): os avisos dela ficam lidos (Fase 8).
  after_commit -> { Whatsapp::Notifier.conversation_read(self) }, on: :update, if: -> { saved_change_to_unread_count? && unread_count.zero? }

  def self.filtered(key)
    case key
    when "nao-lidas" then unread
    when "leads" then where.not(lead_id: nil)
    when "clientes" then where.not(contact_id: nil)
    when "sem-vinculo" then unlinked
    when "janela" then window_open
    else all
    end
  end

  # Contador do menu: conversas com mensagem e não lidas, numa consulta só.
  def self.menu_unread_count
    with_messages.unread.count
  end

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
    unless linked?
      self.lead_id, self.contact_id, self.linked_at, self.linked_by_id = other.slice(:lead_id, :contact_id, :linked_at, :linked_by_id).values
      self.auto_link_blocked_at = linked? ? nil : [ auto_link_blocked_at, other.auto_link_blocked_at ].compact.max
    end
    other.interactions.find_each do |interaction|
      taken = interactions.exists?(subject_type: interaction.subject_type, subject_id: interaction.subject_id, occurred_on: interaction.occurred_on)
      interaction.update_columns(whatsapp_conversation_id: id) unless taken
    end
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
    record_interaction(message.sent_at.to_date) if interaction_message?(message)
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

  # Liga a conversa ao lead ou ao contato e tira a marca de desvinculada. Sem user, é o vínculo
  # automático pelo telefone.
  def link!(record, user: nil)
    assign_link(record, user: user)
    save!
  end

  # Desvincula e marca: o vínculo automático não liga de novo até o telefone da conversa mudar.
  def unlink!
    update!(lead: nil, contact: nil, linked_at: nil, linked_by: nil, auto_link_blocked_at: Time.current)
  end

  def auto_link_blocked?
    auto_link_blocked_at.present?
  end

  # Leads e contatos com o telefone da conversa, no WhatsApp ou no telefone do cadastro.
  def matching_leads
    forms = Whatsapp::Phone.stored_forms(wa_id)
    forms.empty? ? Lead.none : Lead.where(whatsapp_digits: forms).or(Lead.where(phone_digits: forms))
  end

  def matching_contacts
    forms = Whatsapp::Phone.stored_forms(wa_id)
    forms.empty? ? Contact.none : Contact.where(whatsapp_digits: forms).or(Contact.where(phone_digits: forms))
  end

  # Vincula sozinha quando há um só candidato: um lead em aberto ou um contato. Leads convertidos
  # e perdidos não contam, mas aparecem como sugestão no painel. A desvinculada à mão fica de fora.
  def auto_link!
    return false if linked? || wa_id.nil? || auto_link_blocked?

    auto_link
    linked? && save!
  end

  # Onde fica a interação "WhatsApp" do dia: o lead em aberto; o lead convertido, na oportunidade
  # aberta que ele virou; o contato, na oportunidade aberta da empresa. Sem oportunidade aberta,
  # o contato fica sem interação (a conversa aparece no card da empresa) e o lead perdido, no lead.
  def interaction_subject
    if lead
      lead.open? ? lead : (lead.opportunities.open.order(updated_at: :desc).first || lead)
    elsif contact
      contact.company.opportunities.open.order(updated_at: :desc).first
    end
  end

  # Destinatário na Cloud API: o telefone quando a conversa tem (a Meta continua mandando o
  # telefone nos webhooks de quem recebe por ele); senão, o BSUID. Com os dois, `to` vence.
  def recipient_params
    wa_id ? { to: wa_id } : { recipient: bsuid }
  end

  # O nome salvo na agenda do celular vem antes do nome do perfil, que a própria pessoa escolhe.
  def display_name
    saved_name || profile_name || phone_label || (username && "@#{username.delete_prefix('@')}") || "Contato do WhatsApp"
  end

  # +55 11 99102-3344 para celular e fixo do Brasil; os outros países, só com o +.
  def phone_label
    return unless wa_id

    match = wa_id.match(/\A55(\d{2})(\d{4,5})(\d{4})\z/)
    match ? "+55 #{match[1]} #{match[2]}-#{match[3]}" : "+#{wa_id}"
  end

  # Envio só com a conta conectada; desconectada ou com o token vencido, a conversa fica só leitura.
  def sendable?
    account.connected?
  end

  def read_only_reason
    case account.status
    when "connected" then nil
    when "disconnected" then "O número está desconectado. Conecte de novo em Integrações → WhatsApp para voltar a enviar."
    when "reconnect_required" then "O acesso à Meta venceu. Reconecte o número em Integrações → WhatsApp para voltar a enviar."
    else "O número ainda está sendo conectado. O envio fica liberado quando a ativação terminar."
    end
  end

  def to_s
    display_name
  end

  # Redesenha o cabeçalho e o campo de envio da conversa aberta (janela que abriu ou fechou).
  def broadcast_window_change
    broadcast_replace_later_to self, :whatsapp, target: ActionView::RecordIdentifier.dom_id(self, :header),
                                                partial: "whatsapp_conversations/header", locals: { conversation: self }
    broadcast_replace_later_to self, :whatsapp, target: ActionView::RecordIdentifier.dom_id(self, :composer),
                                                partial: "whatsapp_conversations/composer", locals: { conversation: self }
  end

  private

  def assign_link(record, user:)
    self.lead, self.contact = record.is_a?(Lead) ? [ record, nil ] : [ nil, record ]
    self.linked_at, self.linked_by = Time.current, user
    self.auto_link_blocked_at = nil
  end

  # Telefone novo: a marca de desvinculada à mão cai e o vínculo automático pode tentar de novo. O
  # mesmo número em outra forma (com ou sem o nono dígito, devolvido pela Meta) não é telefone novo.
  def phone_changed
    return if Whatsapp::Phone.same_number?(wa_id_in_database, wa_id)

    self.auto_link_blocked_at = nil
    auto_link unless linked?
  end

  def auto_link
    candidates = matching_leads.open.limit(2).to_a + matching_contacts.limit(2).to_a
    assign_link(candidates.first, user: nil) if candidates.one?
  end

  # Mensagem que conta na interação do dia: da conversa de agora (não do histórico), sem reação
  # nem aviso do sistema, e que não falhou.
  def interaction_message?(message)
    linked? && !message.from_history? && !message.kind_reaction? && !message.kind_system? && !message.status_failed?
  end

  # Depois do commit, para o job contar a mensagem que acabou de entrar.
  def record_interaction(day)
    ActiveRecord.after_all_transactions_commit { WhatsappInteractionJob.perform_later(self, day.iso8601) }
  end

  # Vínculo novo: a interação de hoje (se já houve mensagem) e o painel da conversa aberta. O painel
  # vem como turbo-frame com src, carregado por quem está vendo, porque mostra dados do CRM conforme
  # a permissão de cada um.
  def link_changed
    record_interaction(Date.current) if linked?
    broadcast_replace_later_to self, :whatsapp, target: ActionView::RecordIdentifier.dom_id(self, :panel),
                                                partial: "whatsapp_conversations/panel_frame", locals: { conversation: self }
  end

  # Caixa de entrada da conta e contador do menu. Nova mensagem leva o item ao topo (sai de onde
  # estiver, inclusive das páginas carregadas depois); o resto só redesenha o item.
  def broadcast_inbox
    return if last_message_at.nil?

    item = { partial: "whatsapp_conversations/inbox_item", locals: { conversation: self } }
    if saved_change_to_last_message_at? || previously_new_record?
      broadcast_remove_to account, :whatsapp_inbox, target: ActionView::RecordIdentifier.dom_id(self, :inbox)
      broadcast_prepend_later_to account, :whatsapp_inbox, target: ActionView::RecordIdentifier.dom_id(account, :inbox), **item
    elsif saved_changes.keys.intersect?(INBOX_ATTRIBUTES)
      broadcast_replace_later_to account, :whatsapp_inbox, target: ActionView::RecordIdentifier.dom_id(self, :inbox), **item
    end
    if saved_change_to_unread_count? || saved_change_to_last_message_at?
      broadcast_replace_later_to :whatsapp_menu, target: "whatsapp_menu_counter", partial: "whatsapp_conversations/menu_counter"
    end
    window_was_open = last_inbound_at_before_last_save.present? && last_inbound_at_before_last_save > WINDOW.ago
    broadcast_window_change if saved_change_to_last_inbound_at? && window_was_open != window_open?
  end

  def identified
    errors.add(:base, "Informe o ID do WhatsApp (BSUID) ou o telefone") if bsuid.blank? && wa_id.blank?
  end

  def single_link
    errors.add(:base, "A conversa liga a um lead ou a um contato, não aos dois") if lead_id.present? && contact_id.present?
  end
end
