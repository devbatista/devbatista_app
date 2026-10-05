module Admin
  # Configurações editáveis sem deploy (RF 42).
  class SettingsController < ApplicationController
    def show
      authorize Setting, :index?
      @tab = params[:aba].presence || "geral"
    end

    def update
      authorize Setting, :update?
      values = settings_params
      Setting.transaction { values.each { |key, value| Setting[key] = value } }
      redirect_to admin_settings_path(aba: params[:aba]), notice: "Configurações salvas."
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_settings_path(aba: params[:aba]), alert: e.record.errors.full_messages.to_sentence
    end

    private

    # Converte os campos do formulário para o tipo de cada configuração.
    def settings_params
      raw = params.require(:settings).permit(:company_name, :company_legal_name, :company_site, :mailer_sender,
                                             :email_enabled, :daily_run_time, :proposal_alert_days, :recurrence_months,
                                             contract_alert_days: [], domain_alert_days: [], loss_reasons: [],
                                             expense_categories: [], cost_centers: [])
      raw.to_h.to_h do |key, value|
        case Setting::DEFAULTS[key]
        when Array then [ key, Array(value).compact_blank.map { |v| v.to_s.match?(/\A\d+\z/) ? v.to_i : v.strip }.uniq.then { |list| list.all?(Integer) ? list.sort.reverse : list } ]
        when Integer then [ key, value.to_i ]
        when true, false then [ key, value == "1" ]
        else [ key, value.to_s.strip ]
        end
      end
    end
  end
end
