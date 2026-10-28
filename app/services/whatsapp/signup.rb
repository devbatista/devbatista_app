module Whatsapp
  # Conexão de um número pelo Embedded Signup (docs/specs/whatsapp, Fase 4). Roda na própria
  # requisição, porque o code vale 30 segundos:
  #   1. troca o code pelo token;
  #   2. lê no debug_token a validade do token e as WABAs liberadas;
  #   3. cria ou atualiza a conta pelo phone_number_id (reconectar reaproveita as conversas);
  #   4. enfileira a ativação (WhatsappActivationJob).
  #
  #   Whatsapp::Signup.new(code: code, user: user, session: { phone_number_id:, waba_id:, business_id:, is_on_biz_app: }).call
  #
  # O session info vem da janela da Meta (mensagem WA_EMBEDDED_SIGNUP). Sem ele, a WABA sai do
  # debug_token e o número, de GET /<WABA>/phone_numbers. O token não vai para o log.
  class Signup
    # As WABAs liberadas ficam nos target_ids destes escopos.
    SCOPES = %w[whatsapp_business_management whatsapp_business_messaging].freeze

    def initialize(code:, user:, session: {})
      @code = code
      @user = user
      @session = session.to_h.symbolize_keys.reject { |_key, value| value.nil? || value == "" } # false fica (is_on_biz_app)
    end

    def call
      token = Client.exchange_code(@code)
      info = Client.debug_token(token)
      check!(info)
      wabas = granted_wabas(info)
      from_session = @session.values_at(:phone_number_id, :waba_id).all?(&:present?)
      check_session!(wabas) if from_session
      ids = from_session ? @session : discover(token, wabas)

      account = WhatsappAccount.find_or_initialize_by(phone_number_id: ids[:phone_number_id].to_s)
      account.assign_attributes(WhatsappAccount.connection_attributes(token: token, token_expires_at: expires_at(info), user: @user,
                                                                      reset_marks: account.disconnected?))
      account.assign_attributes({ waba_id: ids[:waba_id].to_s, business_id: @session[:business_id], coexistence: coexistence,
                                  display_phone_number: ids[:display_phone_number], verified_name: ids[:verified_name] }.compact)
      account.save!
      Rails.logger.info("[Whatsapp] número conectado pelo Embedded Signup: phone_number_id=#{account.phone_number_id} " \
                        "waba_id=#{account.waba_id} coexistencia=#{account.coexistence?} session_info=#{from_session}")
      WhatsappActivationJob.perform_later(account)
      account
    end

    private

    def check!(info)
      raise Error, "A Meta informou que o acesso concedido não é válido. Tente conectar de novo." unless info["is_valid"]
      raise Error, "O acesso foi concedido a outro app da Meta." unless info["app_id"].to_s == Whatsapp.config.app_id.to_s
    end

    # WABAs liberadas no token (target_ids dos escopos do WhatsApp).
    def granted_wabas(info)
      Array(info["granular_scopes"]).select { |scope| SCOPES.include?(scope["scope"]) }
                                    .flat_map { |scope| Array(scope["target_ids"]).map(&:to_s) }.uniq
    end

    # O session info vem do navegador: a WABA tem de estar entre as liberadas no token. Sem
    # target_ids no debug_token, não há com o que conferir.
    def check_session!(wabas)
      return if wabas.empty? || wabas.include?(@session[:waba_id].to_s)

      Rails.logger.warn("[Whatsapp] WABA do session info (#{@session[:waba_id]}) fora dos target_ids do token (#{wabas.join(', ')})")
      raise Error, "A conta informada pela janela da Meta não corresponde à autorização. Conecte de novo."
    end

    # Sem session info: a WABA liberada no token e o único número dela. Com vários números, fica
    # o que ainda não está conectado no Admin.
    def discover(token, waba_ids)
      raise Error, "A Meta não informou a conta do WhatsApp autorizada. Conecte de novo e conclua todas as etapas da janela." if waba_ids.empty?

      numbers = waba_ids.flat_map do |waba_id|
        Client.new(WhatsappAccount.new(waba_id: waba_id, access_token: token)).phone_numbers.map { |number| number.merge("waba_id" => waba_id) }
      end
      if numbers.size > 1
        connected = WhatsappAccount.connected.where(phone_number_id: numbers.pluck("id")).pluck(:phone_number_id)
        numbers = numbers.reject { |number| connected.include?(number["id"]) }
      end
      raise Error, "Não foi possível identificar o número autorizado. Conecte de novo e conclua todas as etapas da janela." unless numbers.one?

      number = numbers.first
      { phone_number_id: number["id"], waba_id: number["waba_id"], display_phone_number: number["display_phone_number"],
        verified_name: number["verified_name"] }
    end

    # expires_at 0 é token sem validade.
    def expires_at(info)
      seconds = info["expires_at"].to_i
      Time.zone.at(seconds) if seconds.positive?
    end

    # is_on_biz_app do session info; sem ele, a ativação lê no phone_number_details.
    def coexistence
      ActiveModel::Type::Boolean.new.cast(@session[:is_on_biz_app]) if @session.key?(:is_on_biz_app)
    end
  end
end
