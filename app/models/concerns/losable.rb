# Saída "Perdido" do pipeline: pode ocorrer em qualquer etapa aberta e exige o motivo,
# escolhido na lista configurável (Administração → Configurações → Motivos de perda).
module Losable
  extend ActiveSupport::Concern

  included do
    validates :lost_reason, presence: { message: "é obrigatório para marcar como perdido" }, if: :lost?
    validates :lost_reason, inclusion: { in: ->(_) { Setting[:loss_reasons] }, message: "não está na lista de motivos" },
                            if: -> { lost? && will_save_change_to_lost_reason? }
  end

  def mark_lost!(reason:, details: nil)
    update!(status_attribute => "lost", lost_reason: reason, lost_details: details)
  end
end
