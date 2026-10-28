module Commercial
  # Registro manual de interações no lead ou na oportunidade. O formulário também abre na gaveta
  # (new), a partir do painel da conversa do WhatsApp, e volta para a página de onde veio.
  class InteractionsController < ApplicationController
    before_action :set_subject

    def new
      @interaction = @subject.interactions.new(occurred_on: Date.current, kind: "call", user: current_user)
      authorize @interaction, :create?
    end

    def create
      interaction = @subject.interactions.new(params.expect(interaction: %i[kind occurred_on notes]).merge(user: current_user))
      authorize interaction, :create?
      if interaction.save
        redirect_back fallback_location: (@subject.is_a?(Lead) ? lead_path(@subject) : opportunities_path), notice: "Interação registrada."
      else
        redirect_back fallback_location: root_path, alert: interaction.errors.full_messages.to_sentence
      end
    end

    private

    def set_subject
      @subject = params[:lead_id] ? Lead.find(params[:lead_id]) : Opportunity.find(params[:opportunity_id])
      authorize @subject, :update?
    end
  end
end
