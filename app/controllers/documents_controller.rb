class DocumentsController < ApplicationController
  def index
    authorize Document
    scope = policy_scope(Document).includes(:company, :uploaded_by, :documentable, file_attachment: :blob)
    @counts = scope.group(:kind).count
    scope = scope.where(kind: params[:tipo]) if Document.kinds.key?(params[:tipo])
    scope = scope.where(company_id: params[:empresa]) if params[:empresa].present?
    scope = scope.where("unaccent(documents.title) ILIKE unaccent(?)", "%#{Document.sanitize_sql_like(params[:q].strip)}%") if params[:q].present?
    @documents, @pager = paginate(scope.recent)
    @companies = Company.by_name.select(:id, :trade_name)
    @total_bytes = ActiveStorage::Blob.joins(:attachments).where(active_storage_attachments: { record_type: "Document" }).sum(:byte_size)
  end

  def new
    link = find_link
    @document = authorize Document.new(documentable: link, kind: link.is_a?(Contract) ? "contract" : "other")
  end

  def create
    @document = Document.new(document_params)
    @document.uploaded_by = current_user
    authorize @document
    if @document.save
      redirect_to return_path, notice: "Documento enviado."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # Abre o arquivo (URL assinada e temporária do Active Storage).
  def show
    @document = authorize Document.find(params[:id])
    redirect_to rails_blob_path(@document.file, disposition: params[:baixar] ? "attachment" : "inline"), allow_other_host: false
  end

  def destroy
    @document = authorize Document.find(params[:id])
    @document.destroy!
    redirect_to documents_path, notice: "Documento excluído.", status: :see_other
  end

  private

  # Só aceita vínculo com os tipos permitidos; qualquer outro é descartado antes de carregar.
  def document_params
    permitted = params.expect(document: %i[title kind documentable_type documentable_id notes file])
    return permitted if permitted[:documentable_type].in?(Document::LINKABLE_TYPES)

    permitted.except(:documentable_type, :documentable_id)
  end

  def find_link
    if params[:contrato].present? then Contract.find(params[:contrato])
    elsif params[:empresa].present? then Company.find(params[:empresa])
    end
  end

  def return_path
    case @document.documentable
    when Contract then contract_path(@document.documentable)
    when Company then params[:voltar] == "empresa" ? company_path(@document.documentable, aba: "documentos") : documents_path
    else documents_path
    end
  end
end
