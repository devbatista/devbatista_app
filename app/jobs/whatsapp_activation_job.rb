# Ativação de um número conectado pelo Embedded Signup (docs/specs/whatsapp, Fase 4). Etapas, na
# ordem; cada uma grava sua marca na conta e é pulada quando já foi feita, então o job retoma de
# onde parou ("Tentar de novo" na tela) e a renovação do token, que mantém as marcas, não repete
# nada:
#   1. inscreve o app nos webhooks da WABA (subscribed_at);
#   2. lê nome, qualidade, limite e coexistência (phone_number_details). É uma leitura, refeita a
#      cada execução para valer o estado atual do número;
#   3. sem coexistência e sem registro na Cloud API (platform_type), para em "Aguardando registro"
#      até a tela receber o PIN (registered_at). Com coexistência, o número já está registrado;
#   4. com coexistência, pede a sincronização dos contatos e depois a do histórico, uma única vez
#      cada (contacts_sync_request_id, history_sync_request_id). A Meta dá 24h depois da conexão;
#   5. conectado.
# O status final só é gravado se a conta ainda estiver em "Conectando": uma desconexão que chegue
# pelo webhook durante a ativação prevalece.
# Falha transitória tenta de novo; a definitiva fica em activation_error, em português.
class WhatsappActivationJob < ApplicationJob
  SYNC_COLUMNS = { contacts: :contacts_sync_request_id, history: :history_sync_request_id }.freeze
  # Sincronização já pedida antes (2593107), sem o request_id: fica este marcador na coluna, para
  # não pedir de novo.
  ALREADY_REQUESTED = "already-requested".freeze
  # Já pedida (2593107) ou fora das 24h (2593108): não adianta tentar de novo. O número fica
  # conectado e, se nenhuma sincronização chegou, a tela explica o caminho.
  SYNC_ERRORS = [ 2_593_107, 2_593_108 ].freeze
  SYNC_REMEDY = "Para sincronizar, desconecte no celular e conecte o número de novo.".freeze

  self.log_arguments = false
  queue_as :default
  discard_on ActiveJob::DeserializationError
  retry_on Whatsapp::Error, wait: :polynomially_longer, attempts: 5 do |job, error|
    job.arguments.first.fail_activation!(error)
  end

  def perform(account)
    return unless account.pending?

    account.update!(activation_error: nil)
    client = Whatsapp::Client.new(account)
    subscribe(account, client)
    details = client.phone_number_details
    account.update!(WhatsappAccount.attributes_from_phone_details(details))
    return finish(account, "registration_pending") if registration_needed?(account, details)

    request_syncs(account, client) if account.coexistence?
    return unless finish(account, "connected")

    Rails.logger.info("[Whatsapp] número ativado: phone_number_id=#{account.phone_number_id}")
  rescue Whatsapp::Error => e
    raise if e.transient?

    account.fail_activation!(e)
  end

  private

  def subscribe(account, client)
    return if account.subscribed_at
    raise Whatsapp::Error, "A Meta não confirmou a inscrição do app nos webhooks da conta." unless client.subscribe_app

    account.update!(subscribed_at: Time.current)
  end

  def registration_needed?(account, details)
    !account.coexistence? && account.registered_at.nil? && details["platform_type"] != "CLOUD_API"
  end

  # Um pedido por tipo, com a conta travada e relida: dois jobs ao mesmo tempo não pedem duas
  # vezes, e conta desconectada no meio da ativação não pede.
  def request_syncs(account, client)
    SYNC_COLUMNS.each do |type, column|
      account.with_lock do
        account.update!(column => client.request_sync(type)) if account.pending? && account[column].blank?
      end
    rescue Whatsapp::Error => e
      raise unless SYNC_ERRORS.include?(e.code)

      sync_failed(account, column, e)
    end
  end

  def sync_failed(account, column, error)
    attributes = error.code == 2_593_107 ? { column => ALREADY_REQUESTED } : {}
    attributes[:activation_error] = "#{error.user_message} #{SYNC_REMEDY}" if error.code == 2_593_108 || !account.sync_received?
    account.update!(attributes) if attributes.any?
  end

  # Grava o status com a conta travada e relida, só se ela ainda estiver em "Conectando".
  def finish(account, status)
    account.with_lock { account.pending? && account.update!(status: status) }
  end
end
