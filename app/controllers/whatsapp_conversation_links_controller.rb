# Vínculo da conversa com o CRM (docs/specs/whatsapp, Fase 7a). "Vincular" abre na gaveta lateral:
# sem busca, mostra os cadastros com o telefone da conversa; com busca, nome, empresa, e-mail e
# telefone. Os candidatos do painel vinculam com um clique (create com o alvo). Só entram os leads
# e contatos que a pessoa pode ler.
class WhatsappConversationLinksController < ApplicationController
  RESULTS = 8

  before_action :set_conversation

  def new
    @term = params[:q].to_s.strip
    @leads, @contacts =
      if @term.present?
        [ policy_scope(Lead).whatsapp_search(@term), policy_scope(Contact).whatsapp_search(@term) ]
      else
        [ policy_scope(@conversation.matching_leads), policy_scope(@conversation.matching_contacts) ]
      end
    @leads = @leads.order(Arel.sql("CASE WHEN leads.status IN ('new', 'contacted', 'qualified') THEN 0 ELSE 1 END"), :name).limit(RESULTS)
    @contacts = @contacts.includes(:company).order(:name).limit(RESULTS)
  end

  def create
    record = target
    @conversation.link!(record, user: current_user)
    save_phone(record) if params[:salvar_telefone] == "1"
    redirect_to whatsapp_conversation_path(@conversation), notice: "Conversa vinculada #{record.is_a?(Lead) ? 'ao lead' : 'ao contato'} #{record}."
  end

  def destroy
    @conversation.unlink!
    redirect_to whatsapp_conversation_path(@conversation), notice: "Conversa desvinculada.", status: :see_other
  end

  private

  def set_conversation
    @conversation = authorize WhatsappConversation.find(params[:whatsapp_conversation_id]), :link?
  end

  # "Lead:<id>" ou "Contact:<id>".
  def target
    type, id = params.require(:alvo).to_s.split(":", 2)
    case type
    when "Lead" then policy_scope(Lead).find(id)
    when "Contact" then policy_scope(Contact).find(id)
    else raise ActiveRecord::RecordNotFound
    end
  end

  # O telefone da conversa vai para o WhatsApp do cadastro só quando ele está vazio.
  def save_phone(record)
    return if @conversation.wa_id.nil? || record.whatsapp.present? || !policy(record).update?

    record.update(whatsapp: Whatsapp::Phone.national_label(@conversation.wa_id))
  end
end
