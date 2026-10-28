# WhatsApp → Conversas (docs/specs/whatsapp, Fase 6): caixa de entrada, conversa aberta e painel,
# em três colunas, atualizadas pelos Turbo Streams (WhatsappStreamsChannel).
#
# A lista e a conversa são turbo-frames: filtrar e buscar recarrega só a lista ("whatsapp_inbox"),
# abrir uma conversa recarrega só ela ("whatsapp_conversation"). As duas paginam por cursor: a
# lista pela última mensagem e a linha do tempo pela data e o id da mensagem, sem pular nem repetir
# quando chega mensagem nova.
class WhatsappConversationsController < ApplicationController
  INBOX_PAGE = 30
  THREAD_PAGE = 50

  before_action :set_conversation, only: %i[show messages read]

  def index
    authorize WhatsappConversation
    load_inbox
    render :inbox_page, layout: false if params[:cursor_id].present?
  end

  # Abrir a conversa zera as não lidas e marca a última recebida como lida na Meta.
  def show
    load_inbox unless turbo_frame_request?
    mark_as_read
    @messages, @older = thread_page(@conversation.messages)
  end

  # "Carregar mensagens anteriores" (turbo-frame no topo da linha do tempo).
  def messages
    before = @conversation.messages.find(params[:before])
    @messages, @older = thread_page(@conversation.messages.before_cursor(before))
    render layout: false
  end

  # Mensagem recebida com a conversa aberta e a aba visível.
  def read
    mark_as_read
    head :no_content
  end

  private

  def set_conversation
    @conversation = authorize WhatsappConversation.includes(:account, :lead, contact: :company).find(params[:id])
    @account = @conversation.account
  end

  def load_inbox
    @accounts = policy_scope(WhatsappAccount).order(:created_at).to_a
    @account ||= @accounts.find { |account| account.id == params[:conta] } || @accounts.reject(&:disconnected?).first || @accounts.first
    return unless @account

    base = policy_scope(WhatsappConversation).where(account: @account).with_messages
    base = base.search(params[:q]) if params[:q].present?
    @filter = WhatsappConversation::FILTERS.key?(params[:filtro]) ? params[:filtro] : "todas"
    @counts = filter_counts(base)
    scope = base.filtered(@filter).inbox_order.includes(:lead, contact: :company)
    scope = scope.after_cursor(cursor) if params[:cursor_id].present?
    page = scope.limit(INBOX_PAGE + 1).to_a
    @conversations = page.first(INBOX_PAGE)
    @next_cursor = @conversations.last if page.size > INBOX_PAGE
  end

  # Contagem de cada filtro numa consulta só.
  def filter_counts(scope)
    window = WhatsappConversation.sanitize_sql([ "last_inbound_at > ?", WhatsappConversation::WINDOW.ago ])
    values = scope.pick(Arel.sql("count(*), count(*) FILTER (WHERE unread_count > 0), count(*) FILTER (WHERE lead_id IS NOT NULL), " \
                                 "count(*) FILTER (WHERE contact_id IS NOT NULL), count(*) FILTER (WHERE lead_id IS NULL AND contact_id IS NULL), " \
                                 "count(*) FILTER (WHERE #{window})"))
    WhatsappConversation::FILTERS.keys.zip(values).to_h
  end

  def cursor
    WhatsappConversation.new(id: params[:cursor_id], last_message_at: Time.zone.parse(params[:cursor_at].to_s))
  end

  # Página da linha do tempo, da mais nova para trás, devolvida em ordem cronológica. older: há mais antes.
  def thread_page(scope)
    page = scope.timeline.reorder(sent_at: :desc, id: :desc).limit(THREAD_PAGE + 1)
                .includes(:user, :reply_to, :reactions, media_attachment: :blob).to_a
    [ page.first(THREAD_PAGE).reverse, page.size > THREAD_PAGE ]
  end

  def mark_as_read
    @conversation.update!(unread_count: 0) if @conversation.unread_count.positive?
    pending = @conversation.messages.inbound.where(from_history: false, read_at: nil).where.not(wa_message_id: nil)
    WhatsappReadJob.perform_later(@conversation) if @conversation.sendable? && pending.exists?
  end
end
