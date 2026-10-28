module Whatsapp
  # Falha numa chamada à Graph API, com o erro da Meta já separado:
  #   { "error": { "message", "type", "code", "error_subcode", "error_data": { "details" }, "fbtrace_id", "is_transient" } }
  # Falha de rede ou timeout vira o mesmo erro, com code nil e transient? verdadeiro;
  # delivery_uncertain? diz se o pedido pode ter sido processado pela Meta mesmo assim.
  class Error < StandardError
    # Códigos de limite de envio ou de chamadas: tentar de novo mais tarde.
    RATE_LIMIT_CODES = [ 4, 80_007, 130_429, 131_056 ].freeze
    TRANSIENT_CODES = [ 1, 2, 131_000 ].freeze
    # Não adianta tentar de novo logo, mesmo que a Meta marque is_transient: pagamento, qualidade
    # do número (131048), limite de marketing por pessoa (131049, só depois de 24h), conta
    # bloqueada, número sem registro e bloqueio por política.
    NO_RETRY_CODES = [ 131_042, 131_048, 131_049, 131_031, 133_010, 368 ].freeze

    # Mensagens em português para os códigos que a tela mostra (docs da Meta, "error codes").
    MESSAGES = {
      190 => "O acesso ao WhatsApp expirou ou foi revogado. Conecte o número de novo.",
      368 => "A conta do WhatsApp Business está bloqueada temporariamente por violação de política da Meta.",
      131_031 => "A conta do WhatsApp Business está bloqueada pela Meta (violação de política ou PIN de verificação incorreto).",
      131_042 => "Há um problema com a forma de pagamento da conta do WhatsApp Business. Confira o faturamento no Gerenciador do WhatsApp.",
      131_048 => "O número está com limite de envio porque mensagens anteriores foram bloqueadas ou marcadas como spam. " \
                 "Confira a qualidade no Gerenciador do WhatsApp.",
      131_049 => "A Meta não entregou esta mensagem de marketing para preservar o engajamento. Espere pelo menos 24h para reenviar.",
      133_010 => "O número não está registrado na Cloud API. Conclua o registro antes de enviar.",
      133_005 => "O PIN da verificação em duas etapas não confere.",
      133_016 => "O número passou do limite de 10 tentativas de registro em 72 horas. Tente de novo depois.",
      131_047 => "A janela de 24h está fechada. Envie um template aprovado.",
      131_026 => "A mensagem não pôde ser entregue a esse contato.",
      131_051 => "Tipo de mensagem não suportado.",
      131_053 => "Não foi possível enviar a mídia. Confira o formato e o tamanho do arquivo.",
      131_056 => "Muitas mensagens para o mesmo contato em pouco tempo. Tente de novo em instantes.",
      131_062 => "Esta mensagem não pode ser enviada sem o telefone do contato.",
      130_403 => "Este contato foi bloqueado pela empresa.",
      132_000 => "A quantidade de variáveis não confere com o template.",
      132_001 => "O template não existe nesse idioma ou ainda não foi aprovado.",
      132_012 => "Uma variável do template está em formato inválido.",
      2_593_107 => "A sincronização com o app do celular já foi feita para este número.",
      2_593_108 => "O prazo de 24h para sincronizar com o app do celular acabou."
    }.freeze

    attr_reader :code, :subcode, :details, :fbtrace_id, :http_status

    def self.from_response(response)
      error = (JSON.parse(response.body.to_s)["error"] if response.body.present?) || {}
      new(error["message"].presence || "HTTP #{response.code}",
          code: error["code"], subcode: error["error_subcode"], details: error.dig("error_data", "details"),
          fbtrace_id: error["fbtrace_id"], http_status: response.code.to_i, transient: error["is_transient"])
    rescue JSON::ParserError
      new("HTTP #{response.code}", http_status: response.code.to_i)
    end

    def initialize(message, code: nil, subcode: nil, details: nil, fbtrace_id: nil, http_status: nil, transient: nil, network: false, uncertain: false)
      super(message)
      @code = code
      @subcode = subcode
      @details = details
      @fbtrace_id = fbtrace_id
      @http_status = http_status
      @transient = transient
      @network = network
      @uncertain = network && uncertain
    end

    def network?
      @network
    end

    # Falha de rede depois que o pedido saiu (leitura que expirou, conexão interrompida, resposta
    # inválida): a Meta pode ter processado. No envio de mensagem, tentar de novo pode duplicar.
    def delivery_uncertain?
      @uncertain
    end

    def token_invalid?
      code == 190
    end

    def window_closed?
      code == 131_047
    end

    def rate_limited?
      RATE_LIMIT_CODES.include?(code)
    end

    # Vale tentar de novo: rede, erro do servidor da Meta, limite de chamadas ou erro marcado como
    # transitório, menos os de NO_RETRY_CODES.
    def transient?
      return false if NO_RETRY_CODES.include?(code)

      network? || @transient == true || rate_limited? || TRANSIENT_CODES.include?(code) || http_status.to_i >= 500
    end

    def user_message
      MESSAGES.fetch(code) { network? ? "Não foi possível falar com a Meta agora. Tente de novo em instantes." : details.presence || message }
    end
  end
end
