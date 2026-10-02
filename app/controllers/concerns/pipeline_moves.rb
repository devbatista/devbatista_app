# Mudança de etapa pelo quadro do pipeline (arrastar) e saída "Perdido" com motivo.
# Usado por Leads e Oportunidades; cada controller define `pipeline_record`.
module PipelineMoves
  extend ActiveSupport::Concern

  def move
    record = pipeline_record
    authorize record, :update?
    attribute = record.is_a?(Lead) ? :status : :stage
    allowed = record.is_a?(Lead) ? Lead::OPEN_STATUSES : Opportunity::OPEN_STAGES + %w[won]
    value = params[:to].to_s

    if value.in?(allowed) && record.update(attribute => value)
      respond_to do |format|
        format.json { render json: { ok: true, label: record.public_send("#{attribute}_label") } }
        format.html { redirect_back fallback_location: pipeline_path, notice: "Etapa atualizada." }
      end
    else
      message = record.errors.full_messages.to_sentence.presence || "Essa mudança de etapa não é permitida aqui."
      respond_to do |format|
        format.json { render json: { ok: false, error: message }, status: :unprocessable_entity }
        format.html { redirect_back fallback_location: pipeline_path, alert: message }
      end
    end
  end

  def new_loss
    @record = pipeline_record
    authorize @record, :update?
    render "shared/loss_form"
  end

  def lose
    @record = pipeline_record
    authorize @record, :update?
    if @record.open? && @record.update(loss_params.merge((@record.is_a?(Lead) ? :status : :stage) => "lost"))
      redirect_to after_loss_path, notice: "Marcado como perdido: #{@record.lost_reason}."
    else
      @record.errors.add(:base, "Só registros em aberto podem ser marcados como perdidos") unless @record.open?
      render "shared/loss_form", status: :unprocessable_entity
    end
  end

  private

  def loss_params
    params.expect(loss: %i[lost_reason lost_details])
  end

  def after_loss_path
    params[:voltar] == "pipeline" ? pipeline_path : url_for(controller: controller_name, action: :index)
  end
end
