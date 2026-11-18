# "Iniciar conversa no WhatsApp" com um lead ou contato (docs/specs/whatsapp, Fase 7b), na gaveta
# lateral. O primeiro contato é sempre por template aprovado.
# - Sem destinatário ("Nova conversa" na tela de conversas): busca os leads e contatos com WhatsApp
#   cadastrado. Com destinatário (lead_id ou contact_id, nos cards do CRM): o formulário do template,
#   com as variáveis já preenchidas pelo cadastro.
# - Sem número válido no cadastro, pede o número e pode salvá-lo no cadastro.
# - A conversa é a do cadastro nesta conta, a do mesmo número (com e sem o nono dígito) ou uma
#   nova, ligada ao cadastro depois do envio. Número numa conversa ligada a outro cadastro é recusado.
# - Com fatura (fatura=<id>, na tela da fatura emitida; docs/specs/faturas): as variáveis da fatura
#   e o link público vêm preenchidos, o PDF vai no cabeçalho de documento e o envio marca a fatura
#   como enviada.
class WhatsappConversationStartsController < ApplicationController
  include WhatsappDeliveryParams

  RESULTS = 10

  before_action :authorize_start

  def new
    @recipient = find_recipient
    return search unless @recipient

    @invoice = find_invoice

    prepare_form
  end

  def create
    @recipient = find_recipient || raise(ActiveRecord::RecordNotFound)
    @invoice = find_invoice
    prepare_form
    @error = start
    if @error
      render :new, status: :unprocessable_content
    elsif @invoice
      @invoice.mark_sent!
      redirect_to invoice_path(@invoice), notice: "Fatura #{@invoice.code} enviada pelo WhatsApp para #{@recipient.name}."
    else
      redirect_to whatsapp_conversation_path(@conversation), notice: "Template enviado para #{@recipient.name}."
    end
  end

  private

  def authorize_start
    authorize WhatsappMessage, :create?
    authorize WhatsappConversation, :link?
  end

  def find_recipient
    if params[:lead_id].present?
      policy_scope(Lead).find(params[:lead_id])
    elsif params[:contact_id].present?
      policy_scope(Contact).includes(:company).find(params[:contact_id])
    end
  end

  # Fatura emitida do próprio contato, para quem pode ver o Financeiro.
  def find_invoice
    return if params[:fatura].blank? || !@recipient.is_a?(Contact)

    invoice = policy_scope(Invoice).issued.find_by(id: params[:fatura], contact_id: @recipient.id)
    invoice if invoice && policy(invoice).update?
  end

  # PDF da fatura como arquivo enviado, para o cabeçalho de documento do template.
  def invoice_pdf_upload
    pdf = InvoicePdf.new(@invoice, view_url: invoice_link)
    file = Tempfile.new([ "fatura", ".pdf" ], binmode: true)
    file.write(pdf.render)
    file.rewind
    ActionDispatch::Http::UploadedFile.new(tempfile: file, filename: pdf.filename, type: "application/pdf")
  end

  def invoice_token
    @invoice_token ||= @invoice.generate_token_for(:client_view)
  end

  def invoice_link
    invoice_view_url(invoice_token)
  end

  # Leads e contatos com WhatsApp cadastrado; os leads em aberto primeiro.
  def search
    @term = params[:q].to_s.strip
    leads = policy_scope(Lead).where.not(whatsapp_digits: nil)
    contacts = policy_scope(Contact).where.not(whatsapp_digits: nil)
    leads, contacts = leads.whatsapp_search(@term), contacts.whatsapp_search(@term) if @term.present?
    @leads = leads.order(Arel.sql("CASE WHEN leads.status IN ('new', 'contacted', 'qualified') THEN 0 ELSE 1 END"), updated_at: :desc).limit(RESULTS)
    @contacts = contacts.includes(:company).order(:name).limit(RESULTS)
    render :search
  end

  def prepare_form
    @accounts = policy_scope(WhatsappAccount).connected.order(:created_at).to_a
    @account = @accounts.find { |account| account.id == params[:conta] } || @accounts.first
    @needs_number = Whatsapp::Phone.wa_ids(@recipient.whatsapp).empty?
    @number = @needs_number ? params[:numero].to_s.strip : @recipient.whatsapp
    @existing = @recipient.whatsapp_conversations.with_messages.where(account: @account).order(last_message_at: :desc).first if @account
    person = Whatsapp::TemplateFields.person(@recipient)
    person = person.merge(Whatsapp::TemplateFields.invoice(@invoice, link: invoice_link, token: invoice_token)) if @invoice
    @templates = Array(@account&.templates&.usable).map do |template|
      Whatsapp::TemplateFields.new(template).to_h(person: person, values: (template_values if template.id == params[:template_id]))
    end
  end

  # Envia o template e devolve o erro em português, ou nil.
  def start
    return "Nenhum número do WhatsApp conectado. Conecte em Tecnologia → Integrações → WhatsApp." unless @account

    wa_ids = Whatsapp::Phone.wa_ids(@number)
    return "Informe o WhatsApp de #{first_name} com DDD, como (11) 98765-4321." if wa_ids.empty?

    conversation = @recipient.whatsapp_conversations.where(account: @account).order(Arel.sql("last_message_at DESC NULLS LAST")).first ||
                   @account.conversations.find_by(wa_id: wa_ids) || WhatsappConversation.locate!(@account, wa_id: wa_ids.first)
    # Nova só se o locate! a criou agora: ele pode devolver a que o webhook criou no mesmo instante.
    created = conversation.previously_new_record?
    if !created && conversation.linked? && conversation.link != @recipient
      return "O número #{Whatsapp::Phone.national_label(wa_ids.first)} já está na conversa com #{conversation.link}. Abra a conversa para enviar."
    end
    result = Whatsapp::Outbound.new(conversation, user: current_user)
                               .deliver(kind: "template", template_id: params[:template_id], values: template_values, header_file: header_file)
    if result.error
      discard_empty(conversation) if created
      return result.error
    end

    # A conversa nova pode ter se ligado sozinha pelo telefone: o vínculo fica em nome de quem iniciou.
    conversation.link!(@recipient, user: current_user) if created || conversation.link != @recipient
    save_number(wa_ids.first) if @needs_number && params[:salvar_numero] == "1"
    @conversation = conversation
    nil
  end

  # Apaga a conversa que nasceu vazia para este envio (lida de novo do banco): sem mensagem e sem
  # vínculo feito por alguém. O vínculo automático pelo telefone, feito quando ela nasceu, não conta.
  def discard_empty(conversation)
    conversation.reload
    conversation.destroy! if conversation.messages.none? && (!conversation.linked? || conversation.linked_by_id.nil?)
  end

  # Arquivo enviado na tela ou, com fatura e template de cabeçalho de documento, o PDF dela.
  def header_file
    file = upload(:header_file)
    return file if file || @invoice.nil?

    template = @account.templates.find_by(id: params[:template_id])
    invoice_pdf_upload if template && Whatsapp::TemplateFields.new(template).header_media == "document"
  end

  # O número digitado vai para o WhatsApp do cadastro, que estava vazio ou inválido.
  def save_number(wa_id)
    @recipient.update(whatsapp: Whatsapp::Phone.national_label(wa_id)) if policy(@recipient).update?
  end

  def first_name
    @recipient.name.to_s.split.first
  end
end
