module Commercial
  class ProposalsController < ApplicationController
    before_action :set_proposal, only: %i[show edit update destroy mark new_approval approve new_rejection reject]

    def index
      authorize Proposal
      scope = policy_scope(Proposal).includes(:company, :lead, :user, items: :service)
      @counts = scope.group(:status).count
      scope = scope.where(status: params[:status]) if Proposal.statuses.key?(params[:status])
      scope = scope.where(user_id: params[:responsavel]) if params[:responsavel].present?
      scope = scope.where(company_id: params[:empresa]) if params[:empresa].present?
      scope = scope.search(params[:q]) if params[:q].present?
      scope = apply_sort(scope, {
        "recentes" => [ "Mais recentes", ->(s) { s.order(year: :desc, number: :desc) } ],
        "validade" => [ "Validade mais próxima", ->(s) { s.order(Arel.sql("proposals.status IN ('sent','viewed') DESC"), :valid_until) } ],
        "valor" => [ "Maior valor", ->(s) { s.order(total_cents: :desc) } ]
      })
      @proposals, @pager = paginate(scope)
      @users = User.active.by_name
      @companies = Company.by_name.select(:id, :trade_name)
      month = Date.current.all_month
      decided = Proposal.where(status: %w[approved rejected], decided_on: 90.days.ago.to_date..)
      @kpis = {
        negotiating: Proposal.where(status: %w[sent viewed]).sum(:total_cents),
        negotiating_count: Proposal.where(status: %w[sent viewed]).count,
        expiring: Proposal.where(status: %w[sent viewed], valid_until: Date.current..(Date.current + Setting[:proposal_alert_days].to_i)).count,
        approved_month: Proposal.approved.where(decided_on: month).sum(:total_cents),
        approved_month_count: Proposal.approved.where(decided_on: month).count,
        approval_rate: (decided.approved.count * 100 / decided.count if decided.exists?)
      }
    end

    def show
      @history = AuditLog.where(auditable: @proposal).includes(:user).recent.limit(20)
      @documents = @proposal.documents.includes(:uploaded_by, file_attachment: :blob).recent
    end

    def new
      opportunity = Opportunity.find_by(id: params[:oportunidade])
      @proposal = authorize Proposal.new(
        company_id: params[:empresa] || opportunity&.company_id, lead_id: params[:lead], opportunity: opportunity,
        title: opportunity&.title, user: current_user, valid_until: Date.current + 15, status: "draft"
      )
      @proposal.items.build(service: opportunity&.service || Service.available.first)
    end

    def create
      @proposal = authorize Proposal.new(proposal_params)
      if @proposal.save
        redirect_to @proposal, notice: "Proposta #{@proposal.code} criada como rascunho."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      redirect_to @proposal, alert: "Proposta #{@proposal.status_label.downcase} não pode mais ser editada." unless @proposal.editable?
    end

    def update
      return redirect_to(@proposal, alert: "Proposta #{@proposal.status_label.downcase} não pode mais ser editada.") unless @proposal.editable?

      if @proposal.update(proposal_params)
        redirect_to @proposal, notice: "Proposta atualizada."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      return redirect_to(@proposal, alert: "Só rascunhos podem ser excluídos.") unless @proposal.draft?

      @proposal.destroy!
      redirect_to proposals_path, notice: "Rascunho excluído.", status: :see_other
    end

    # Enviada (registro de envio) e Visualizada (marcação manual, sem portal no MVP).
    def mark
      to = params[:to].to_s
      allowed = { "sent" => %w[draft], "viewed" => %w[sent] }
      if allowed.fetch(to, []).include?(@proposal.status) && @proposal.update(status: to)
        @proposal.opportunity&.update(stage: "proposal") if to == "sent" && @proposal.opportunity&.stage_meeting?
        redirect_to @proposal, notice: "Proposta marcada como #{@proposal.status_label.downcase}."
      else
        redirect_to @proposal, alert: @proposal.errors.full_messages.to_sentence.presence || "Mudança de status não permitida."
      end
    end

    def new_approval
      @approval = ProposalApproval.new(proposal: @proposal)
    end

    def approve
      @approval = ProposalApproval.new(proposal: @proposal, **params.expect(approval: %i[approved_on start_date end_date due_day renewal]).to_h.symbolize_keys)
      authorize Contract, :create?
      if @approval.save
        redirect_to contract_path(@approval.contract), notice: "Negócio fechado: contrato #{@approval.contract.code} e #{@proposal.items.size} serviços contratados criados a partir da proposta #{@proposal.code}."
      else
        render :new_approval, status: :unprocessable_entity
      end
    end

    def new_rejection; end

    def reject
      if (@proposal.sent? || @proposal.viewed?) &&
         @proposal.update(params.expect(rejection: %i[rejection_reason rejection_details]).merge(status: "rejected"))
        @proposal.opportunity&.mark_lost!(reason: @proposal.rejection_reason, details: @proposal.rejection_details) if @proposal.opportunity&.open?
        redirect_to @proposal, notice: "Recusa registrada."
      else
        @proposal.errors.add(:base, "Só proposta Enviada ou Visualizada pode ser recusada") unless @proposal.sent? || @proposal.viewed? || @proposal.rejected?
        render :new_rejection, status: :unprocessable_entity
      end
    end

    private

    def set_proposal
      @proposal = Proposal.find(params[:id])
      authorize @proposal, %w[show].include?(action_name) ? :show? : (action_name == "destroy" ? :destroy? : :update?)
    end

    def proposal_params
      params.expect(proposal: [ :title, :company_id, :lead_id, :opportunity_id, :contact_id, :user_id, :description, :payment_terms,
                                :delivery_terms, :valid_until, :notes,
                                items_attributes: [ [ :id, :service_id, :description, :recurrence, :price, :position, :_destroy ] ] ])
    end
  end
end
