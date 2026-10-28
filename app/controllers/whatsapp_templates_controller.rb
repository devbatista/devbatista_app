# WhatsApp → Templates (docs/specs/whatsapp, Fase 5): lista, prévia, sincronização com a Meta,
# criação, edição e exclusão. O Whatsapp::TemplateBuilder valida os campos e monta os components.
class WhatsappTemplatesController < ApplicationController
  STATUS_FILTERS = %w[approved pending rejected paused].freeze
  before_action :set_template, only: %i[show edit update destroy]

  def index
    authorize WhatsappTemplate
    load_accounts
    return unless @account

    scope = policy_scope(WhatsappTemplate).where(account: @account).current
    @counts = scope.group(:status).count
    @latest_rejected = scope.status_rejected.order(updated_at: :desc).first
    scope = scope.where(status: params[:status]) if STATUS_FILTERS.include?(params[:status])
    scope = scope.search(params[:q]) if params[:q].present?
    @templates, @pager = paginate(scope.order(:name, :language))
  end

  def show
    @builder = Whatsapp::TemplateBuilder.from_template(@template)
  end

  def new
    authorize WhatsappTemplate
    load_accounts
    return redirect_to(whatsapp_templates_path, alert: no_account_message) if editor_accounts.empty?

    @account = editor_accounts.find { |account| account.id == params[:conta] } || editor_accounts.first
    @builder = Whatsapp::TemplateBuilder.new
  end

  def create
    authorize WhatsappTemplate
    load_accounts
    @account = editor_accounts.find { |account| account.id == params.dig(:template, :account_id) }
    return redirect_to(whatsapp_templates_path, alert: no_account_message) unless @account

    @builder = Whatsapp::TemplateBuilder.new(builder_params)
    client = Whatsapp::Client.new(@account)
    @builder.upload_sample(sample_file, client) if @builder.media_header? && sample_file
    return render_editor(:new) unless @builder.valid?
    return render_editor(:new, "Já existe o template #{@builder.name} em #{@builder.language} nesta conta.") if duplicate?

    created = client.create_template(**@builder.template_attributes)
    template = @account.templates.create!(@builder.template_attributes.merge(meta_attributes(created)))
    redirect_to whatsapp_templates_path(conta: @account.id), notice: created_notice(template)
  rescue Whatsapp::Error => e
    render_editor(:new, e.user_message)
  end

  def edit
    return redirect_to(whatsapp_templates_path(conta: @template.whatsapp_account_id), alert: not_editable_message) unless @template.editable?

    @builder = Whatsapp::TemplateBuilder.from_template(@template)
  end

  # Nome e idioma não mudam; a categoria de um aprovado também não. Volta para análise.
  def update
    return redirect_to(whatsapp_templates_path(conta: @template.whatsapp_account_id), alert: not_editable_message) unless @template.editable?
    return redirect_to(whatsapp_templates_path(conta: @template.whatsapp_account_id), alert: @template.account.templates_sync_blocked_reason) unless @template.account.templates_syncable?

    locked = { name: @template.name, language: @template.language }
    locked[:category] = @template.category if @template.status_approved?
    @builder = Whatsapp::TemplateBuilder.new(builder_params.merge(locked))
    client = Whatsapp::Client.new(@template.account)
    @builder.upload_sample(sample_file, client) if @builder.media_header? && sample_file
    return render_editor(:edit) unless @builder.valid?

    category = @builder.category unless @builder.category == @template.category
    client.update_template(@template.meta_template_id, components: @builder.components, category: category)
    @template.update!(components: @builder.components, category: @builder.category, status: "pending", rejection_reason: nil)
    redirect_to whatsapp_templates_path(conta: @template.whatsapp_account_id), notice: "#{@template.name} enviado de novo para análise da Meta."
  rescue Whatsapp::Error => e
    render_editor(:edit, e.user_message)
  end

  # Exclui só aquele idioma na Meta (hsm_id). No banco, fica como excluído.
  def destroy
    back = whatsapp_templates_path(conta: @template.whatsapp_account_id)
    return redirect_to(back, alert: "Este template já foi excluído.") unless @template.deletable?
    return redirect_to(back, alert: "Há envio em andamento com #{@template.name}. Espere terminar para excluir.") if @template.pending_sends?
    return redirect_to(back, alert: @template.account.templates_sync_blocked_reason) unless @template.account.templates_syncable?

    Whatsapp::Client.new(@template.account).delete_template(name: @template.name, meta_template_id: @template.meta_template_id) if @template.meta_template_id
    @template.update!(status: "deleted")
    redirect_to back, notice: "#{@template.name} excluído. O nome só pode ser usado de novo depois de 30 dias.", status: :see_other
  rescue Whatsapp::Error => e
    redirect_to back, alert: "Não foi possível excluir: #{e.user_message}", status: :see_other
  end

  def sync
    authorize WhatsappTemplate, :sync?
    account = WhatsappAccount.find(params[:conta])
    return redirect_to(whatsapp_templates_path(conta: account.id), alert: account.templates_sync_blocked_reason) unless account.templates_syncable?

    account.update!(templates_sync_requested_at: Time.current, templates_sync_error: nil)
    WhatsappTemplateSyncJob.perform_later(account)
    redirect_to whatsapp_templates_path(conta: account.id), notice: "Sincronização com a Meta iniciada."
  end

  private

  def set_template
    @template = authorize WhatsappTemplate.find(params[:id])
  end

  # Contas com template ou conectadas; a primeira não desconectada é a padrão.
  def load_accounts
    @accounts = policy_scope(WhatsappAccount).order(:created_at).to_a
    @account ||= @accounts.find { |account| account.id == params[:conta] } || @accounts.reject(&:disconnected?).first || @accounts.first
  end

  # Só contas com o acesso à Meta válido criam templates.
  def editor_accounts
    @accounts.select(&:templates_syncable?)
  end

  def builder_params
    params.require(:template).permit(:name, :language, :category, :header_type, :header_text, :header_example, :header_handle,
                                     :body, :footer, body_examples: [], buttons: %i[type text url url_example phone]).to_h
  end

  def sample_file
    file = params.dig(:template, :header_file)
    file if file.respond_to?(:content_type)
  end

  def duplicate?
    @account.templates.current.exists?(name: @builder.name, language: @builder.language)
  end

  # Status e categoria devolvidos pela Meta na criação (a categoria pode mudar).
  def meta_attributes(created)
    data = { "id" => created["id"], "name" => @builder.name, "status" => created["status"] || "PENDING", "category" => created["category"] }
    WhatsappTemplate.attributes_from_meta(data, current: WhatsappTemplate.new(category: @builder.category)).slice(:meta_template_id, :status, :category)
  end

  def created_notice(template)
    notice = "#{template.name} enviado para análise da Meta."
    template.category == @builder.category ? notice : "#{notice} A Meta classificou como #{template.category_label}."
  end

  def render_editor(view, alert = nil)
    flash.now[:alert] = alert if alert
    render view, status: :unprocessable_entity
  end

  def no_account_message
    "Nenhum número com acesso válido à Meta. Conecte ou reconecte em Integrações → WhatsApp."
  end

  def not_editable_message
    "Só templates aprovados, rejeitados ou pausados podem ser editados na Meta. Autenticação fica só para leitura."
  end
end
