# Envio pelo Admin, "Tentar de novo" e mídia das conversas do WhatsApp (docs/specs/whatsapp, Fase 6).
# O envio vai pelo Whatsapp::Outbound (confere a conta e a janela) e pelo WhatsappSendJob. A
# resposta acrescenta o balão "Enviando" na hora; o broadcast do mesmo balão, com o mesmo id, só o
# substitui (o Turbo não duplica).
class WhatsappMessagesController < ApplicationController
  include ActiveStorage::SetCurrent
  include WhatsappDeliveryParams

  def create
    @conversation = WhatsappConversation.includes(:account).find(params[:whatsapp_conversation_id])
    authorize WhatsappMessage.new(conversation: @conversation)

    result = Whatsapp::Outbound.new(@conversation, user: current_user).deliver(**delivery_params)
    respond(result, body: (params[:body] if result.error))
  end

  def retry
    original = authorize WhatsappMessage.includes(conversation: :account).find(params[:id])
    @conversation = original.conversation
    respond(Whatsapp::Outbound.new(@conversation, user: current_user).retry(original))
  end

  # Mídia da conversa: só com permissão, por uma URL temporária do serviço (5 minutos), nunca permanente.
  def media
    message = authorize WhatsappMessage.find(params[:id])
    return head :not_found unless message.media.attached?

    redirect_to message.media.blob.url(expires_in: 5.minutes, disposition: params[:baixar] ? :attachment : :inline), allow_other_host: true
  end

  private

  def delivery_params
    kind = params[:kind] == "template" ? "template" : "text"
    { kind: kind, body: params[:body], file: upload(:file), reply_to: params[:reply_to].presence,
      template_id: params[:template_id], values: template_values, header_file: upload(:header_file) }
  end

  def respond(result, body: nil)
    respond_to do |format|
      format.turbo_stream do
        status = result.error ? :unprocessable_entity : :ok
        render :create, status: status, locals: { message: result.message, error: result.error, body: body }
      end
      format.html { redirect_to whatsapp_conversation_path(@conversation), alert: result.error, status: :see_other }
    end
  end
end
