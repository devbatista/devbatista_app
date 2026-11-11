# Arquivar e desarquivar a conversa (docs/specs/whatsapp, "Arquivar conversa"), pelo painel. Arquivar
# volta para a lista; desarquivar fica na conversa.
class WhatsappConversationArchivesController < ApplicationController
  before_action :set_conversation

  def create
    @conversation.archive!(current_user)
    redirect_to whatsapp_conversations_path(conta: @conversation.whatsapp_account_id),
                notice: "Conversa arquivada. Ela volta para a lista quando chegar mensagem nova.", status: :see_other
  end

  def destroy
    @conversation.unarchive!
    redirect_to whatsapp_conversation_path(@conversation), notice: "Conversa desarquivada.", status: :see_other
  end

  private

  def set_conversation
    @conversation = authorize WhatsappConversation.find(params[:whatsapp_conversation_id]), :archive?
  end
end
