module Technology
  # Tecnologia → Integrações → WhatsApp (docs/specs/whatsapp, Fase 4): números conectados e a
  # conexão pelo Embedded Signup. O code, o token e o PIN não vão para log, payload de job nem tela.
  class WhatsappAccountsController < ApplicationController
    # O corpo JSON do Embedded Signup não é embrulhado em whatsapp_account.
    wrap_parameters false
    before_action :set_account, only: %i[register activate]

    def index
      authorize WhatsappAccount
      @accounts = policy_scope(WhatsappAccount).includes(:connected_by).order(:created_at)
      @missing = Whatsapp.missing_signup_configuration
      conversations = WhatsappConversation.with_messages
      @conversation_counts = conversations.group(:whatsapp_account_id).count
      @kpis = {
        conversations: conversations.count, recent: conversations.where(last_message_at: 7.days.ago..).count,
        messages_today: WhatsappMessage.where(sent_at: Time.current.all_day).where.not(kind: %w[reaction system]).group(:direction).count,
        last_webhook_at: @accounts.filter_map(&:last_webhook_at).max
      }
    end

    # Chamado em JSON pelo controller Stimulus whatsapp-signup, com o code e o session info.
    def connect
      authorize WhatsappAccount, :create?
      missing = Whatsapp.missing_signup_configuration
      return render_error("Faltam variáveis de ambiente: #{missing.to_sentence}.") if missing.any?

      signup = params.permit(:code, :phone_number_id, :waba_id, :business_id, :is_on_biz_app)
      return render_error("A Meta não devolveu a autorização. Tente conectar de novo.") if signup[:code].blank?

      account = Whatsapp::Signup.new(code: signup[:code], user: current_user, session: signup.except(:code).to_h).call
      render json: { message: "#{account} autorizado. Ativando o número…", url: whatsapp_accounts_path }
    rescue Whatsapp::Error => e
      render_error("Não foi possível conectar: #{e.user_message}")
    rescue ActiveRecord::ActiveRecordError, ActiveRecord::Encryption::Errors::Base => e
      Rails.logger.error("[Whatsapp] conexão não salva: #{e.class}")
      render_error("Não foi possível salvar a conexão (#{e.class.name.demodulize}). Tente conectar de novo.")
    end

    # Cancelamento na janela da Meta, só para o log: o passo e o código do erro, sem dados pessoais.
    def signup_event
      authorize WhatsappAccount, :create?
      step, code, session = params.values_at(:current_step, :error_code, :session_id).map { |value| value.to_s[/\A[\w.-]{1,64}\z/] }
      Rails.logger.info("[Whatsapp] Embedded Signup cancelado: passo=#{step || '-'}#{" erro=#{code}" if code}#{" session_id=#{session}" if session}")
      head :no_content
    end

    # PIN da verificação em duas etapas do número sem coexistência. Não é salvo.
    def register
      return redirect_to(whatsapp_accounts_path, alert: "Este número não está aguardando registro.") unless @account.registration_pending?

      pin = params[:pin].to_s.strip
      return redirect_to(whatsapp_accounts_path, alert: "O PIN tem 6 dígitos.") unless pin.match?(/\A\d{6}\z/)

      raise Whatsapp::Error, "A Meta não confirmou o registro do número." unless Whatsapp::Client.new(@account).register(pin: pin)

      @account.update!(status: "pending", registered_at: Time.current)
      WhatsappActivationJob.perform_later(@account)
      redirect_to whatsapp_accounts_path, notice: "Número registrado. Concluindo a ativação…"
    rescue Whatsapp::Error => e
      redirect_to whatsapp_accounts_path, alert: "Não foi possível registrar: #{e.user_message}"
    end

    # "Tentar de novo": retoma a ativação da etapa que falhou.
    def activate
      return redirect_to(whatsapp_accounts_path, alert: "Este número não tem ativação para retomar.") unless @account.pending? && @account.activation_error?

      @account.update!(activation_error: nil)
      WhatsappActivationJob.perform_later(@account)
      redirect_to whatsapp_accounts_path, notice: "Ativação retomada."
    end

    private

    def set_account
      @account = authorize WhatsappAccount.find(params[:id]), :update?
    end

    def render_error(message)
      render json: { error: message }, status: :unprocessable_entity
    end
  end
end
