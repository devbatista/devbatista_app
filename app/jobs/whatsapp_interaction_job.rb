# Interação "WhatsApp" automática (docs/specs/whatsapp, Fase 7a): uma por conversa, cadastro e dia,
# no lead ou na oportunidade (WhatsappConversation#interaction_subject), em nome do responsável por
# eles. O texto leva só as contagens do dia, nunca o conteúdo das mensagens, e é refeito a cada
# mensagem: o job pode rodar mais de uma vez para o mesmo dia sem duplicar.
class WhatsappInteractionJob < ApplicationJob
  queue_as :default
  discard_on ActiveJob::DeserializationError

  def perform(conversation, date)
    subject = conversation.interaction_subject
    return unless subject

    day = Date.iso8601(date)
    messages = conversation.messages.where(from_history: false, sent_at: day.in_time_zone.all_day)
                           .where.not(kind: %w[reaction system]).where.not(status: "failed")
    received = messages.inbound.count
    sent = messages.outbound.count
    return if received.zero? && sent.zero?

    notes = "Conversa do dia · #{[ (pluralize(received, 'recebida', 'recebidas') if received.positive?),
                                   (pluralize(sent, 'enviada', 'enviadas') if sent.positive?) ].compact.join(', ')}"
    interaction = Interaction.create_or_find_by!(whatsapp_conversation: conversation, subject: subject, occurred_on: day) do |new_one|
      new_one.assign_attributes(kind: "whatsapp", user: subject.user, notes: notes)
    end
    interaction.update!(notes: notes) if interaction.notes != notes
  end

  private

  def pluralize(count, singular, plural)
    "#{count} #{count == 1 ? singular : plural}"
  end
end
