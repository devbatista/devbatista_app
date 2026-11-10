# Envia texto a um lead pelo WhatsApp da DevBatista (docs/specs/mcp-comercial/README.md). Única tool
# que fala com alguém de fora: as annotations marcam o envio como destrutivo e de mundo aberto, para
# o cliente do Claude pedir confirmação, e a descrição manda simular e esperar o aval do texto exato.
#
# O número sai do WhatsApp do lead e acha a conversa da conta conectada (com e sem o nono dígito). O
# envio passa pelo Whatsapp::Outbound#deliver_now, na hora: a janela de 24h, o limite de texto e a
# duplicidade são conferidos de novo lá, e a mensagem aparece na conversa do Admin como as outras.
# Aceita pela Meta, a conversa fica ligada ao lead e o texto vira interação "WhatsApp" no lead, com o
# wamid (além da interação automática do dia, que só leva as contagens). Recusada, a mensagem fica
# como "Falhou" na conversa e a tool devolve o código e o erro da Meta, sem interação.
module Mcp
  module Tools
    class EnviarWhatsapp < Base
      include CommercialData

      TITLE = "Enviar WhatsApp (requer aprovação)".freeze
      # O mesmo texto ao mesmo lead nesse intervalo é recusado (retry do cliente).
      DUPLICATE_WINDOW = 2.minutes

      tool_name "enviar_whatsapp"
      title TITLE
      description <<~TEXT.squish
        Envia mensagem real ao contato. Só use depois que o usuário aprovou o texto exato no chat; antes, use
        simular: true para mostrar a prévia. Manda um texto ao WhatsApp de um lead em aberto, pelo número da
        DevBatista, e registra a interação no lead. Só funciona dentro da janela de 24h (o contato mandou mensagem
        nas últimas 24h); fora dela, a Meta só aceita template aprovado. O mesmo texto ao mesmo lead é recusado
        por 2 minutos, para não duplicar.
      TEXT
      sends_out title: TITLE
      input_schema(
        properties: {
          lead_id: { type: "string", description: "Id do lead (UUID). O número sai do campo WhatsApp do lead" },
          texto: { type: "string", minLength: 1, maxLength: WhatsappMessage::TEXT_LIMIT,
                   description: "O texto exato que o usuário aprovou, até #{WhatsappMessage::TEXT_LIMIT} caracteres" },
          simular: { type: "boolean", description: "true: só confere e mostra o que seria enviado, sem enviar. Padrão false" }
        },
        required: %w[lead_id texto], additionalProperties: false
      )

      def execute(lead_id:, texto:, simular: false)
        lead = authorize(Lead.find(lead_id), :update?)
        authorize(WhatsappMessage, :create?)
        authorize(WhatsappConversation, :link?)
        interaction = authorize(lead.interactions.new(kind: "whatsapp", occurred_on: Date.current, user: user), :create?)

        body = texto.to_s.strip
        account = policy_scope(WhatsappAccount).connected.order(:created_at).first
        wa_ids = Whatsapp::Phone.wa_ids(lead.whatsapp)
        conversation = conversation_for(account, lead, wa_ids)
        problems = impediments(lead, account, wa_ids, conversation, body)
        return preview(lead, account, wa_ids, conversation, body, problems) if simular

        fail!(problems.first) if problems.any?

        deliver(lead, conversation, body, interaction)
      end

      private

      # A conversa da conta com o número do lead: a já ligada a ele ou a que recebeu por último.
      def conversation_for(account, lead, wa_ids)
        return if account.nil? || wa_ids.empty?

        candidates = account.conversations.where(wa_id: wa_ids).to_a
        candidates.find { |conversation| conversation.lead_id == lead.id } ||
          candidates.max_by { |conversation| conversation.last_inbound_at || Time.zone.at(0) }
      end

      def impediments(lead, account, wa_ids, conversation, body)
        [
          lead_problem(lead),
          phone_problem(lead, wa_ids),
          ("Nenhum número do WhatsApp conectado. Conecte em Tecnologia → Integrações → WhatsApp." unless account),
          link_problem(lead, conversation),
          (window_problem(conversation) if account && wa_ids.any? && !conversation&.window_open?),
          text_problem(body),
          (Whatsapp::Outbound.new(conversation, user: user).duplicate_error(body, DUPLICATE_WINDOW) if conversation && body.present?)
        ].compact
      end

      def lead_problem(lead)
        if lead.status_lost?
          "O lead está como Perdido: não envio WhatsApp para lead perdido. Se ele voltou a conversar, reabra o lead antes."
        elsif lead.status_converted?
          "O lead já foi convertido: não envio WhatsApp pelo lead. A conversa segue pelo cliente, na tela do WhatsApp."
        end
      end

      def phone_problem(lead, wa_ids)
        if lead.whatsapp.blank?
          "O lead não tem WhatsApp cadastrado. Cadastre o número com DDD (atualizar_lead, campo whatsapp) antes de enviar."
        elsif wa_ids.empty?
          "O WhatsApp do lead (#{lead.whatsapp}) não é um número válido. Corrija com DDD, como (11) 98765-4321."
        end
      end

      def link_problem(lead, conversation)
        return unless conversation&.linked? && conversation.lead_id != lead.id

        "O número #{conversation.phone_label} já está na conversa com #{conversation.link.name}. " \
          "Ligue a conversa a este lead na tela do WhatsApp antes de enviar."
      end

      def window_problem(conversation)
        last = conversation&.last_inbound_at
        received = last ? "Última mensagem recebida desse contato: #{last.strftime('%Y-%m-%d %H:%M')}." : "Nenhuma mensagem recebida desse número."
        "Fora da janela de 24h, precisa de template aprovado. #{received}"
      end

      def text_problem(body)
        if body.empty?
          "Escreva o texto da mensagem."
        elsif body.length > WhatsappMessage::TEXT_LIMIT
          "O texto tem #{body.length} caracteres; o limite do WhatsApp é #{WhatsappMessage::TEXT_LIMIT}."
        end
      end

      def preview(lead, account, wa_ids, conversation, body, problems)
        { simulacao: true, pode_enviar: problems.empty?, impedimentos: problems, lead: lead_ref(lead),
          para: conversation&.wa_id || wa_ids.first, texto: body, caracteres: body.length,
          janela_aberta: conversation&.window_open? || false, ultima_recebida_em: conversation&.last_inbound_at&.iso8601,
          janela_fecha_em: conversation&.window_closes_at&.iso8601, numero_devbatista: account&.to_s }
      end

      def deliver(lead, conversation, body, interaction)
        result = Whatsapp::Outbound.new(conversation, user: user).deliver_now(body: body, unique_within: DUPLICATE_WINDOW)
        fail!(failure_text(result)) if result.error

        message = result.message
        { enviado: true, wamid: message.wa_message_id, para: conversation.reload.wa_id, enviado_em: message.sent_at.iso8601 }
          .merge(record_sent(lead, conversation, message, interaction))
      end

      # Depois que a Meta aceitou, nada aqui vira erro da tool: a mensagem já chegou ao contato, e
      # um erro levaria o Claude a tentar de novo.
      def record_sent(lead, conversation, message, interaction)
        conversation.link!(lead, user: user) unless conversation.lead_id == lead.id
        interaction.update!(notes: "WhatsApp enviado pelo Claude · #{message.wa_message_id}\n\n#{message.body}")
        { lead: lead_ref(lead), interacao: interaction_data(interaction).merge(id: interaction.id),
          conversa: link(:whatsapp_conversation, conversation) }
      rescue ActiveRecord::ActiveRecordError => e
        Rails.error.report(e, handled: true, source: "mcp", context: { whatsapp_message: message.id })
        { lead: lead_ref(lead),
          aviso: "A mensagem foi enviada, mas não consegui registrar a interação no lead (#{e.message}). Registre com registrar_interacao." }
      end

      # Erro da Meta com o código e a mensagem original; as recusas do Outbound (janela, duplicidade)
      # e o envio sem confirmação voltam como estão.
      def failure_text(result)
        error = result.meta_error
        return result.error if error.nil? || error.delivery_uncertain?

        prefix = error.network? ? "Não enviado (falha de conexão com a Meta)" : "Não enviado. Erro da Meta#{" (código #{error.code})" if error.code}"
        original = " Mensagem da Meta: #{error.message}" if error.message.present? && error.message != result.error
        "#{prefix}: #{result.error}#{original}"
      end

      def lead_ref(lead)
        { id: lead.id, nome: lead.name }
      end
    end
  end
end
