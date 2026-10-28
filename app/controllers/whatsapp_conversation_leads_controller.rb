# "Criar lead" a partir da conversa (docs/specs/whatsapp, Fase 7a), na gaveta lateral. O lead nasce
# com origem WhatsApp, o nome do perfil (ou da agenda), o telefone e as primeiras mensagens nas
# observações, e a conversa fica ligada a ele.
class WhatsappConversationLeadsController < ApplicationController
  NOTE_LIMIT = 500

  before_action :set_conversation

  def new
    @lead = authorize Lead.new(name: @conversation.saved_name || @conversation.profile_name, whatsapp: Whatsapp::Phone.national_label(@conversation.wa_id),
                               origin: "whatsapp", status: "new", user: current_user, notes: first_messages_note)
  end

  def create
    @lead = authorize Lead.new(lead_params.merge(entered_on: Date.current))
    if Lead.transaction { @lead.save && @conversation.link!(@lead, user: current_user) }
      redirect_to whatsapp_conversation_path(@conversation), notice: "Lead criado e vinculado à conversa."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def set_conversation
    @conversation = authorize WhatsappConversation.find(params[:whatsapp_conversation_id]), :link?
  end

  def lead_params
    params.expect(lead: %i[name company_name whatsapp email origin service_id user_id status notes])
          .tap { |p| p[:status] = "new" unless p[:status].in?(Lead::OPEN_STATUSES) }
  end

  # 'Chegou pelo WhatsApp em 17/09/2026: "…"', com as primeiras mensagens de texto recebidas.
  def first_messages_note
    texts = @conversation.messages.inbound.kind_text.reorder(:sent_at, :id).limit(3).pluck(:body, :sent_at)
    return if texts.empty?

    %(Chegou pelo WhatsApp em #{helpers.date_br(texts.first.last)}: "#{texts.map(&:first).compact_blank.join(' ').truncate(NOTE_LIMIT)}")
  end
end
