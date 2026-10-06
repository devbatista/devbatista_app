module Operations
  # Resposta ao cliente, nota interna ou mensagem do cliente no histórico do chamado,
  # com a opção de já mudar o status ao enviar.
  class TicketMessagesController < ApplicationController
    def create
      ticket = Ticket.find(params[:ticket_id])
      authorize ticket, :update?
      message = ticket.messages.new(params.expect(ticket_message: %i[kind body channel contact_id]).merge(user: current_user))
      authorize message, :create?
      to = params[:status_after].presence_in(Ticket.statuses.keys)

      if message.save
        ticket.update!(status: to) if to && to != ticket.status
        redirect_to ticket_path(ticket, anchor: "historico"), notice: "#{message.kind_label} registrada#{" · chamado #{ticket.status_label}" if to}."
      else
        redirect_to ticket_path(ticket), alert: message.errors.full_messages.to_sentence
      end
    end
  end
end
