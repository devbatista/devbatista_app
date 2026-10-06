module Operations
  class TicketsController < ApplicationController
    before_action :set_ticket, only: %i[show edit update new_status change_status]

    def index
      authorize Ticket
      scope = policy_scope(Ticket).joins(:company).includes(:company, :user, :contact, :app)
      @counts = scope.group(:status).count
      scope = scope.where(status: params[:status]) if Ticket.statuses.key?(params[:status])
      scope = scope.where(priority: params[:prioridade]) if Ticket.priorities.key?(params[:prioridade])
      scope = scope.where(category: params[:categoria]) if Ticket.categories.key?(params[:categoria])
      scope = scope.where(user_id: params[:responsavel]) if params[:responsavel].present?
      scope = scope.where(company_id: params[:empresa]) if params[:empresa].present?
      scope = scope.search(params[:q]) if params[:q].present?
      scope = apply_sort(scope, {
        "criticos" => [ "Críticos primeiro", lambda { |s|
          s.order(Arel.sql("tickets.priority = 'critical' AND tickets.status IN ('open','analyzing','in_progress','waiting_client') DESC"), opened_at: :desc)
        } ],
        "abertura" => [ "Abertura mais recente", ->(s) { s.order(opened_at: :desc) } ],
        "antigos" => [ "Abertos há mais tempo", ->(s) { s.order(Arel.sql("tickets.status IN ('resolved','closed')"), :opened_at) } ]
      })
      @tickets, @pager = paginate(scope)
      @users = User.where(id: Ticket.select(:user_id)).by_name
      @critical = Ticket.open.critical.includes(:company, :user).order(:opened_at).to_a
      @waiting = Ticket.status_waiting_client.includes(:company).order(:opened_at).to_a
      resolved = Ticket.where(resolved_at: 30.days.ago..).to_a
      @kpis = {
        open: Ticket.open.count,
        resolved_count: resolved.size,
        avg_resolution: (resolved.sum(&:resolution_minutes) / resolved.size if resolved.any?)
      }
    end

    def show
      @messages = @ticket.messages.includes(:user, :contact)
      @step_times = step_times
      @hours = @ticket.time_entries.includes(:user).group_by(&:user).transform_values { |entries| entries.sum(&:minutes) }
      @contract = @ticket.company.contracts.current.order(:end_date).first if current_user.can_read?("contratos")
      @related = @ticket.company.tickets.open.where.not(id: @ticket.id).includes(:user).order(opened_at: :desc).limit(5)
    end

    def new
      app = App.find_by(id: params[:aplicacao])
      @ticket = authorize Ticket.new(company_id: params[:empresa] || app&.company_id, app: app, status: "open", priority: "normal", user: current_user)
    end

    def create
      @ticket = authorize Ticket.new(ticket_params)
      if @ticket.save
        redirect_to @ticket, notice: "Chamado #{@ticket.code} aberto#{' — a equipe foi notificada na hora' if @ticket.critical?}."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @ticket.update(ticket_params)
        redirect_to @ticket, notice: "Chamado #{@ticket.code} atualizado."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def new_status
      @status_change = { status: params[:to].presence_in(Ticket.statuses.keys) || next_status }
    end

    # Mudança de status, com mensagem opcional ao cliente registrada no histórico.
    def change_status
      change = params.expect(status_change: %i[status message])
      to = change[:status].to_s
      unless Ticket.statuses.key?(to)
        return redirect_to(@ticket, alert: "Status inválido.")
      end

      Ticket.transaction do
        @ticket.update!(status: to)
        @ticket.messages.create!(kind: "reply", body: change[:message], user: current_user) if change[:message].present?
      end
      note = @ticket.status_resolved? ? " Conclusão registrada em #{I18n.l(@ticket.resolved_at, format: '%d/%m/%Y %H:%M')}." : ""
      redirect_to @ticket, notice: "Chamado #{@ticket.code}: #{@ticket.status_label}.#{note}"
    end

    private

    def set_ticket
      @ticket = Ticket.find(params[:id])
      authorize @ticket, %w[new_status change_status].include?(action_name) ? :update? : "#{action_name}?"
    end

    def ticket_params
      params.expect(ticket: %i[company_id contact_id app_id subject description category priority user_id])
    end

    def next_status
      Ticket::FLOW[Ticket::FLOW.index(@ticket.status) + 1] || @ticket.status
    end

    # Quando o chamado entrou em cada etapa do fluxo, pela trilha de auditoria.
    def step_times
      times = { "open" => @ticket.opened_at }
      AuditLog.where(auditable: @ticket, action: "status_change").order(:created_at).each do |log|
        times[log.changeset.dig("status", 1)] ||= log.created_at
      end
      times
    end
  end
end
