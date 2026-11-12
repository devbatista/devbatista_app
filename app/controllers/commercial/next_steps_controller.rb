module Commercial
  # Comercial → Próximos passos: leads e oportunidades em aberto numa lista só, pela data e hora do
  # próximo passo (NextStepList). "Feito" (NextStepCompletion) e "Adiar" abrem na gaveta e voltam
  # para a lista com os mesmos filtros.
  class NextStepsController < ApplicationController
    FILTERS = %i[periodo tipo origem responsavel voltar].freeze

    before_action :set_record, except: :index
    helper_method :list_filters, :back_path

    def index
      authorize :next_step, :index?
      list = NextStepList.new(leads: policy_scope(Lead), opportunities: policy_scope(Opportunity),
                              kind: params[:tipo].presence_in(NextStepList::KINDS),
                              origin: params[:origem].presence_in(Lead.origins.keys),
                              user_id: params[:responsavel].presence)
      @now = list.now
      @groups = list.groups
      @counts = @groups.transform_values(&:size)
      @period = params[:periodo].presence_in(NextStepList::GROUPS.keys)
      @groups = @groups.slice(@period) if @period
      @users = User.active.by_name
    end

    def new_completion
      @completion = NextStepCompletion.new(record: @record, user: current_user, kind: "whatsapp", outcome: "next_step")
    end

    def complete
      authorize Interaction, :create?
      @completion = NextStepCompletion.new(record: @record, user: current_user, **completion_params)
      if @completion.save
        notice = if @completion.losing? then "Feito e marcado como perdido: #{@record.lost_reason}."
        else "Feito. Próximo passo em #{l(@record.next_step_on, format: '%d/%m às %H:%M')}."
        end
        redirect_to back_path, notice: notice
      else
        render :new_completion, status: :unprocessable_entity
      end
    end

    def new_postponement; end

    def postpone
      time = params[:para] == "escolher" ? NextStepSchedulable.cast(params[:em]) : NextStepSchedulable.postpone_time(params[:para])
      if time.nil?
        @error = "Escolha para quando adiar"
      elsif !@record.open?
        @error = "Só registros em aberto têm próximo passo"
      elsif !@record.update(next_step_on: time)
        @error = @record.errors.full_messages.to_sentence
      end
      return render(:new_postponement, status: :unprocessable_entity) if @error

      redirect_to back_path, notice: "Adiado para #{l(time, format: '%d/%m às %H:%M')}."
    end

    private

    def set_record
      @record = params[:lead_id] ? Lead.find(params[:lead_id]) : Opportunity.find(params[:opportunity_id])
      authorize @record, :update?
    end

    def completion_params
      params.expect(completion: %i[notes kind outcome next_step next_step_on lost_reason lost_details]).to_h.symbolize_keys
    end

    # Filtros da lista (e voltar=ficha, da ficha do lead), levados pela gaveta para a volta.
    def list_filters
      params.slice(*FILTERS).permit(*FILTERS).to_h.compact_blank
    end

    def back_path
      return lead_path(@record) if params[:voltar] == "ficha" && @record.is_a?(Lead)

      next_steps_path(list_filters.except("voltar"))
    end
  end
end
