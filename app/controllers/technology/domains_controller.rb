module Technology
  class DomainsController < ApplicationController
    before_action :set_domain, only: %i[edit update destroy new_renewal renew]

    def index
      authorize Domain
      @windows = Setting[:domain_alert_days].map(&:to_i).sort
      scope = policy_scope(Domain).joins(:company).includes(:company)
      # Faixas do filtro pelos prazos de alerta configurados: "Até 7 dias", "Até 30 dias"... e "Em dia".
      @window_options = @windows.map { |w| [ w.to_s, "Até #{w} dias" ] } + [ [ "em-dia", "Em dia" ] ]
      @counts = @window_options.to_h { |key, _| [ key, window_scope(scope, key).count ] }
      scope = window_scope(scope, params[:prazo]) if @window_options.to_h.key?(params[:prazo])
      scope = scope.where(registrar: params[:registrador]) if params[:registrador].present?
      scope = scope.where(auto_renew: params[:renovacao] == "sim") if %w[sim nao].include?(params[:renovacao])
      scope = scope.search(params[:q]) if params[:q].present?
      @domains, @pager = paginate(scope.by_expiration)
      @registrars = Domain.distinct.order(:registrar).pluck(:registrar)
      all = Domain.includes(:company).by_expiration.to_a
      @urgent = all.select { |d| !d.auto_renew? && d.attention?(Date.current, @windows) }
      @by_window = @windows.index_with { |w| all.select { |d| d.alert_window(Date.current, @windows) == w } }
      @expired = all.select(&:expired?)
      @kpis = { count: all.size, companies: all.map(&:company_id).uniq.size, within: all.count { |d| d.alert_window(Date.current, @windows) },
                manual: all.reject(&:auto_renew?), yearly: all.sum(&:renewal_cost_brl_cents) }
      @last_alerts = Notification.where(kind: "domain_expiring").where(notifiable_type: "Domain").group(:notifiable_id).maximum(:created_at)
    end

    def new
      @domain = authorize Domain.new(company_id: params[:empresa], registrar: "Registro.br", currency: "BRL", paid_by: "client", renewal_cost_cents: 4_000)
    end

    def create
      @domain = authorize Domain.new(domain_params)
      if @domain.save
        redirect_to domains_path, notice: "Domínio #{@domain.name} cadastrado."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @domain.update(domain_params)
        redirect_to domains_path, notice: "Domínio #{@domain.name} atualizado."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @domain.destroy!
      redirect_to domains_path, notice: "Domínio excluído.", status: :see_other
    end

    def new_renewal; end

    def renew
      renewal = params.expect(renewal: %i[expires_on cost auto_renew notes])
      if renewal[:expires_on].present? && Date.parse(renewal[:expires_on]) > @domain.expires_on
        @domain.renew!(expires_on: Date.parse(renewal[:expires_on]), cost: renewal[:cost], auto_renew: renewal[:auto_renew] == "1", notes: renewal[:notes])
        redirect_to domains_path, notice: "Renovação de #{@domain.name} registrada: vence em #{I18n.l(@domain.expires_on)}."
      else
        @domain.errors.add(:expires_on, "precisa ser depois do vencimento atual (#{I18n.l(@domain.expires_on)})")
        render :new_renewal, status: :unprocessable_entity
      end
    end

    private

    def set_domain
      @domain = Domain.find(params[:id])
      authorize @domain, %w[new_renewal renew].include?(action_name) ? :update? : "#{action_name}?"
    end

    def domain_params
      params.expect(domain: %i[company_id name registrar registered_on expires_on auto_renew currency renewal_cost paid_by dns_provider notes])
    end

    # Faixas de vencimento do filtro: até 7, 30 ou 60 dias (cumulativas) ou em dia.
    def window_scope(scope, key)
      today = Date.current
      key == "em-dia" ? scope.where("domains.expires_on > ?", today + @windows.max) : scope.where(expires_on: ..(today + key.to_i))
    end
  end
end
