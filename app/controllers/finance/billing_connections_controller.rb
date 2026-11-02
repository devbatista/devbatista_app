module Finance
  # Conexões de cobrança: fornecedores cujas faturas entram em Despesas pela API.
  class BillingConnectionsController < ApplicationController
    before_action :set_connection, only: %i[edit update destroy sync]

    def index
      authorize BillingConnection
      @connections = policy_scope(BillingConnection).includes(:supplier, :company).by_name.to_a
      month = Date.current.beginning_of_month
      imported = Payable.where(billing_connection_id: @connections.map(&:id)).where.not(status: "cancelled")
      @month_cents = imported.where(competence: month).group(:billing_connection_id).sum(:amount_cents)
      @open_counts = imported.open.group(:billing_connection_id).count
      @recent = imported.includes(:billing_connection).order(competence: :desc, due_on: :desc).limit(12)
    end

    def new
      @connection = authorize BillingConnection.new(provider: params[:provedor].presence_in(BillingConnection::PROVIDERS.keys) || "aws",
                                                    cost_center: "Infraestrutura interna", auto_paid: true)
    end

    def create
      @connection = authorize BillingConnection.new(connection_params)
      if @connection.save
        redirect_to billing_connections_path, notice: "Conexão #{@connection.name} cadastrada. Use \"Sincronizar agora\" para puxar as faturas."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @connection.update(connection_params)
        redirect_to billing_connections_path, notice: "Conexão #{@connection.name} atualizada."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @connection.destroy!
      redirect_to billing_connections_path, notice: "Conexão excluída. As despesas importadas continuam em Despesas.", status: :see_other
    end

    def sync
      result = Billing::Sync.new(@connection).run
      if result
        redirect_to billing_connections_path, notice: "#{@connection.name} sincronizada: #{result}."
      else
        redirect_to billing_connections_path, alert: "Não foi possível sincronizar #{@connection.name}: #{@connection.reload.last_error}"
      end
    end

    private

    def set_connection
      @connection = authorize BillingConnection.find(params[:id]), action_name == "sync" ? :sync? : "#{action_name}?"
    end

    def connection_params
      params.expect(billing_connection: %i[provider name supplier_id account_id cost_center_key auto_paid active])
    end
  end
end
