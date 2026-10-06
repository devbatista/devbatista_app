module Commercial
  # Converter lead em empresa, contato e oportunidade (RF 8).
  class LeadConversionsController < ApplicationController
    before_action :set_lead

    def new
      @conversion = LeadConversion.from(@lead)
    end

    def create
      @conversion = LeadConversion.new(lead: @lead, **conversion_params.to_h.symbolize_keys)
      if @conversion.save
        redirect_to company_path(@conversion.company), notice: "Lead convertido: #{@conversion.company.trade_name} agora tem contato e a oportunidade “#{@conversion.opportunity.title}”."
      else
        render :new, status: :unprocessable_entity
      end
    end

    private

    def set_lead
      @lead = Lead.find(params[:lead_id])
      authorize @lead, :update?
      authorize Company, :create? unless params.dig(:conversion, :company_id).present?
      redirect_to @lead, alert: "Só leads em aberto podem ser convertidos." unless @lead.open?
    end

    def conversion_params
      params.expect(conversion: %i[company_id trade_name legal_name cnpj contact_name contact_position contact_whatsapp contact_email
                                   contact_primary title service_id estimated_value probability expected_close_on stage user_id])
    end
  end
end
