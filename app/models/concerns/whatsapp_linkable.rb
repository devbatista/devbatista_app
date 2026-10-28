# Lead e contato ligados a conversas do WhatsApp. WhatsApp ou telefone novo no cadastro liga as
# conversas sem vínculo com esse número, quando ele é o único candidato (docs/specs/whatsapp, Fase 7a).
module WhatsappLinkable
  extend ActiveSupport::Concern

  included do
    has_many :whatsapp_conversations, dependent: :nullify

    after_commit :link_whatsapp_conversations, on: %i[create update],
                                               if: -> { (saved_change_to_whatsapp? || saved_change_to_phone?) && (whatsapp.present? || phone.present?) }
  end

  private

  def link_whatsapp_conversations
    WhatsappAutoLinkJob.perform_later(self)
  end
end
