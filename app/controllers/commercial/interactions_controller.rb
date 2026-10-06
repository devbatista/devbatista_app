module Commercial
  # Registro manual de interações no lead ou na oportunidade.
  class InteractionsController < ApplicationController
    def create
      subject = params[:lead_id] ? Lead.find(params[:lead_id]) : Opportunity.find(params[:opportunity_id])
      authorize subject, :update?
      interaction = subject.interactions.new(params.expect(interaction: %i[kind occurred_on notes]).merge(user: current_user))
      authorize interaction, :create?
      if interaction.save
        redirect_back fallback_location: (subject.is_a?(Lead) ? lead_path(subject) : opportunities_path), notice: "Interação registrada."
      else
        redirect_back fallback_location: root_path, alert: interaction.errors.full_messages.to_sentence
      end
    end
  end
end
