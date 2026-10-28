require "net/http"

module Whatsapp
  # Cliente da Graph API (Cloud API do WhatsApp), no padrão do BcbPtax: Net::HTTP com timeouts,
  # sem gem nova (docs/specs/whatsapp). Trabalha sobre uma conta conectada (token, WABA e número);
  # a troca do code do Embedded Signup acontece antes de existir conta, em Client.exchange_code.
  #
  #   client = Whatsapp::Client.new(account)
  #   client.send_text(conversation, "Bom dia!")  # => SentMessage(wa_message_id: "wamid...", ...)
  #
  # O destinatário é a conversa (telefone ou BSUID, ver WhatsappConversation#recipient_params) ou um
  # hash { to: } / { recipient: }. Falha da Meta ou de rede levanta Whatsapp::Error. O token nunca
  # vai para o log nem para o inspect.
  class Client
    HOST = "graph.facebook.com".freeze
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 30
    TRANSFER_TIMEOUT = 120 # upload e download de mídia
    NETWORK_ERRORS = [ Timeout::Error, SystemCallError, SocketError, IOError, OpenSSL::SSL::SSLError, Net::HTTPBadResponse ].freeze

    # messaging_limit_tier foi descontinuado; o limite agora é do portfólio, lido no número.
    PHONE_FIELDS = %w[display_phone_number verified_name quality_rating whatsapp_business_manager_messaging_limit
                      is_on_biz_app platform_type name_status code_verification_status].freeze
    TEMPLATE_FIELDS = %w[id name language category status components parameter_format rejected_reason].freeze
    SYNC_TYPES = { contacts: "smb_app_state_sync", history: "history" }.freeze
    MEDIA_TYPES = %w[image audio video document sticker].freeze
    CAPTION_TYPES = %w[image video document].freeze
    # Tamanho máximo por tipo na Cloud API (figurinha animada; a estática tem 100 KB). O download
    # recusa o que passar disso.
    MEDIA_LIMITS = { "image" => 5.megabytes, "audio" => 16.megabytes, "video" => 16.megabytes,
                     "document" => 100.megabytes, "sticker" => 500.kilobytes }.freeze
    MEDIA_LABELS = { "image" => "imagem", "audio" => "áudio", "video" => "vídeo", "document" => "documento", "sticker" => "figurinha" }.freeze

    SentMessage = Data.define(:wa_message_id, :wa_id, :bsuid, :message_status)
    Media = Data.define(:file, :mime_type, :sha256, :size)

    attr_reader :phone_number_id, :waba_id

    # Troca o code do Embedded Signup (vale 30 segundos) pelo token de acesso da conta do cliente.
    def self.exchange_code(code)
      app_id, app_secret = app_credentials
      new.send(:request, :get, "oauth/access_token", auth: false, query: { client_id: app_id, client_secret: app_secret, code: code })
         .fetch("access_token")
    end

    # Dados do token (GET /debug_token, com o token do app app_id|app_secret): app_id, is_valid,
    # expires_at (0 quando não expira) e granular_scopes, com as WABAs liberadas em target_ids.
    def self.debug_token(token)
      app_id, app_secret = app_credentials
      new.send(:request, :get, "debug_token", auth: false, query: { input_token: token, access_token: "#{app_id}|#{app_secret}" })
         .fetch("data")
    end

    def self.app_credentials
      config = Whatsapp.config
      raise Error, "META_APP_ID e META_APP_SECRET não estão configurados" if config.app_id.blank? || config.app_secret.blank?

      [ config.app_id, config.app_secret ]
    end
    private_class_method :app_credentials

    def initialize(account = nil, access_token: account&.access_token, version: Whatsapp.config.graph_version)
      @phone_number_id = account&.phone_number_id
      @waba_id = account&.waba_id
      @access_token = access_token
      @version = version
    end

    def inspect
      "#<#{self.class.name} phone_number_id=#{phone_number_id.inspect} waba_id=#{waba_id.inspect}>"
    end

    # ---------- Mensagens ----------

    def send_text(recipient, body, preview_url: false, reply_to: nil)
      send_message(recipient, "text", { body: body, preview_url: preview_url }, reply_to: reply_to)
    end

    # Mídia já enviada (media_id, de upload_media) ou por URL pública (link).
    def send_media(recipient, type:, media_id: nil, link: nil, caption: nil, filename: nil, reply_to: nil)
      raise ArgumentError, "tipo de mídia inválido: #{type}" unless MEDIA_TYPES.include?(type.to_s)
      raise ArgumentError, "informe media_id ou link" if media_id.blank? && link.blank?

      content = media_id.present? ? { id: media_id } : { link: link }
      content[:caption] = caption if caption.present? && CAPTION_TYPES.include?(type.to_s)
      content[:filename] = filename if filename.present? && type.to_s == "document"
      send_message(recipient, type.to_s, content, reply_to: reply_to)
    end

    # components no formato da Cloud API; monte com Whatsapp::TemplateComponents.build.
    def send_template(recipient, name:, language:, components: [], reply_to: nil)
      template = { name: name, language: { code: language } }
      template[:components] = components if components.present?
      send_message(recipient, "template", template, reply_to: reply_to)
    end

    # Marca a mensagem recebida (e as anteriores da conversa) como lida.
    def mark_as_read(wa_message_id)
      request(:post, "#{phone_number_id}/messages", json: { messaging_product: "whatsapp", status: "read", message_id: wa_message_id })
      true
    end

    # ---------- Mídia ----------

    def upload_media(io, filename:, mime_type:)
      form = [ [ "messaging_product", "whatsapp" ], [ "type", mime_type ], [ "file", io, { filename: filename, content_type: mime_type } ] ]
      request(:post, "#{phone_number_id}/media", form: form, timeout: TRANSFER_TIMEOUT).fetch("id")
    end

    # URL temporária (vale 5 minutos), tipo, sha256 e tamanho da mídia.
    def media(media_id)
      request(:get, media_id, query: { phone_number_id: phone_number_id }.compact)
    end

    # Baixa a mídia para um Tempfile, confere o sha256 e devolve Media. Quem chama fecha o arquivo.
    # Recusa antes de baixar se o file_size da Meta passar do limite do tipo (MEDIA_LIMITS) e
    # interrompe o download se o total passar dele, mesmo sem file_size.
    def download_media(media_id)
      info = media(media_id)
      type = self.class.media_type(info["mime_type"])
      uri = URI(info.fetch("url"))
      size = info["file_size"].presence&.to_i
      raise log(media_too_large(type, size), :get, uri.path) if size && size > MEDIA_LIMITS.fetch(type)

      file = Tempfile.new([ "whatsapp-media", "" ], binmode: true)
      digest = Digest::SHA256.new
      total = 0
      stream(uri) do |chunk|
        total += chunk.bytesize
        raise log(media_too_large(type), :get, uri.path) if total > MEDIA_LIMITS.fetch(type)

        file.write(chunk)
        digest << chunk
      end
      file.rewind
      if info["sha256"].present? && digest.hexdigest != info["sha256"]
        raise log(Error.new("a mídia baixada não confere com o sha256 da Meta"), :get, uri.path)
      end

      Media.new(file: file, mime_type: info["mime_type"], sha256: digest.hexdigest, size: file.size)
    rescue StandardError
      file&.close!
      raise
    end

    def delete_media(media_id)
      request(:delete, media_id, query: { phone_number_id: phone_number_id }.compact)
      true
    end

    # Tipo de mídia da Cloud API pelo mime_type: image/webp é figurinha; o que não for imagem,
    # áudio ou vídeo é documento.
    def self.media_type(mime_type)
      mime = mime_type.to_s.split(";").first.to_s.strip.downcase
      return "sticker" if mime == "image/webp"

      family = mime.split("/").first
      %w[image audio video].include?(family) ? family : "document"
    end

    # ---------- Templates ----------

    # Todos os templates da conta, seguindo a paginação. Categoria e status vêm em maiúsculas
    # (ver WhatsappTemplate.attributes_from_meta).
    def templates
      results = []
      after = nil
      loop do
        page = request(:get, "#{waba_id}/message_templates", query: { fields: TEMPLATE_FIELDS.join(","), limit: 100, after: after }.compact)
        results.concat(page.fetch("data", []))
        after = page.dig("paging", "cursors", "after")
        break if page.dig("paging", "next").blank? || after.blank?
      end
      results
    end

    # => { "id", "status", "category" }
    def create_template(name:, language:, category:, components:, allow_category_change: false)
      request(:post, "#{waba_id}/message_templates",
              json: { name: name, language: language, category: category.to_s.upcase, components: components,
                      allow_category_change: allow_category_change })
    end

    # Só templates aprovados, rejeitados ou pausados podem ser editados; a categoria de um aprovado não muda.
    def update_template(meta_template_id, components:)
      request(:post, meta_template_id, json: { components: components })
      true
    end

    # Com o ID, apaga só aquele idioma; sem ele, todos os idiomas do nome.
    def delete_template(name:, meta_template_id: nil)
      request(:delete, "#{waba_id}/message_templates", query: { name: name, hsm_id: meta_template_id }.compact)
      true
    end

    # ---------- Conta ----------

    # Inscreve o app nos webhooks da conta do cliente.
    def subscribe_app
      request(:post, "#{waba_id}/subscribed_apps").fetch("success", false)
    end

    def unsubscribe_app
      request(:delete, "#{waba_id}/subscribed_apps").fetch("success", false)
    end

    def subscribed_apps
      request(:get, "#{waba_id}/subscribed_apps").fetch("data", [])
    end

    def phone_number_details
      request(:get, phone_number_id, query: { fields: PHONE_FIELDS.join(",") })
    end

    # Números da WABA: id, display_phone_number e verified_name.
    def phone_numbers
      request(:get, "#{waba_id}/phone_numbers", query: { fields: "id,display_phone_number,verified_name" }).fetch("data", [])
    end

    # Registra na Cloud API um número sem coexistência (cliente sem o app do celular), depois do
    # Embedded Signup; a coexistência não usa. O pin é o da verificação em duas etapas: o atual, se
    # o número já tiver, ou o novo. Não guardar. A Meta aceita 10 tentativas por número em 72h.
    def register(pin:)
      raise ArgumentError, "o PIN tem 6 dígitos" unless pin.to_s.match?(/\A\d{6}\z/)

      request(:post, "#{phone_number_id}/register", json: { messaging_product: "whatsapp", pin: pin.to_s }).fetch("success", false)
    end

    # Coexistência: pede à Meta a sincronização dos contatos (:contacts) ou do histórico (:history)
    # do app do celular. Uma vez por tipo e só nas 24h depois da conexão. Devolve o request_id.
    def request_sync(type)
      sync_type = SYNC_TYPES.fetch(type)
      request(:post, "#{phone_number_id}/smb_app_data", json: { messaging_product: "whatsapp", sync_type: sync_type }).fetch("request_id")
    end

    private

    attr_reader :access_token, :version

    def send_message(recipient, type, content, reply_to: nil)
      payload = { messaging_product: "whatsapp", recipient_type: "individual" }
      payload.merge!(recipient.respond_to?(:recipient_params) ? recipient.recipient_params : recipient.to_h)
      payload[:type] = type
      payload[type.to_sym] = content
      payload[:context] = { message_id: reply_to } if reply_to.present?
      data = request(:post, "#{phone_number_id}/messages", json: payload)
      message = Array(data["messages"]).first || {}
      contact = Array(data["contacts"]).first || {}
      SentMessage.new(wa_message_id: message["id"], wa_id: contact["wa_id"], bsuid: contact["user_id"], message_status: message["message_status"])
    end

    def request(method, path, query: nil, json: nil, form: nil, auth: true, timeout: READ_TIMEOUT)
      uri = URI("https://#{HOST}/#{version}/#{path}")
      uri.query = URI.encode_www_form(query) if query.present?
      req = { get: Net::HTTP::Get, post: Net::HTTP::Post, delete: Net::HTTP::Delete }.fetch(method).new(uri)
      req["Authorization"] = "Bearer #{access_token}" if auth
      if json
        req["Content-Type"] = "application/json"
        req.body = JSON.generate(json)
      elsif form
        req.set_form(form, "multipart/form-data")
      end
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: OPEN_TIMEOUT, read_timeout: timeout) { |http| http.request(req) }
      raise log(Error.from_response(response), method, uri.path) unless response.is_a?(Net::HTTPSuccess)

      response.body.present? ? JSON.parse(response.body) : {}
    rescue *NETWORK_ERRORS => e
      raise log(Error.new("#{e.class}: #{e.message}", network: true), method, uri&.path)
    end

    # Download em pedaços (até 100 MB), com o token: a URL da mídia exige autenticação.
    def stream(uri, &block)
      req = Net::HTTP::Get.new(uri)
      req["Authorization"] = "Bearer #{access_token}"
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: OPEN_TIMEOUT, read_timeout: TRANSFER_TIMEOUT) do |http|
        http.request(req) do |response|
          raise log(Error.from_response(response), :get, uri.path) unless response.is_a?(Net::HTTPSuccess)

          response.read_body(&block)
        end
      end
    rescue *NETWORK_ERRORS => e
      raise log(Error.new("#{e.class}: #{e.message}", network: true), :get, uri.path)
    end

    def media_too_large(type, size = nil)
      limit = "#{ActiveSupport::NumberHelper.number_to_human_size(MEDIA_LIMITS.fetch(type))} para #{MEDIA_LABELS.fetch(type)}"
      return Error.new("A mídia passou do limite de #{limit} durante o download.") unless size

      Error.new("A mídia tem #{ActiveSupport::NumberHelper.number_to_human_size(size)} e passa do limite de #{limit}.")
    end

    # Só método, caminho (sem query) e o erro da Meta: nada de token, segredo ou conteúdo de mensagem.
    def log(error, method, path)
      Rails.logger.warn("[Whatsapp] #{method.to_s.upcase} #{path}: #{error.message}" \
                        "#{" code=#{error.code}" if error.code}#{" fbtrace_id=#{error.fbtrace_id}" if error.fbtrace_id}")
      error
    end
  end
end
