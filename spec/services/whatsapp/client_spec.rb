require "rails_helper"

RSpec.describe Whatsapp::Client do
  let(:account) { build(:whatsapp_account, waba_id: "1029384756102938", phone_number_id: "6655443322110099", access_token: "EAAG-token-secreto") }
  let(:client) { described_class.new(account) }
  let(:sent) { graph_response(200, { "messaging_product" => "whatsapp", "contacts" => [ { "input" => "5511991023344", "wa_id" => "5511991023344" } ], "messages" => [ { "id" => "wamid.ENVIADA1" } ] }) }

  describe "envio de mensagens" do
    it "envia texto para o telefone, com o token no cabeçalho e a mensagem citada" do
      requests = stub_graph(sent)
      conversation = build(:whatsapp_conversation, wa_id: "5511991023344")
      result = client.send_text(conversation, "Confirmando: terça às 10h.", reply_to: "wamid.CITADA")

      request = requests.first
      expect(request.method).to eq("POST")
      expect(request.uri.to_s).to eq("https://graph.facebook.com/v26.0/6655443322110099/messages")
      expect(request["Authorization"]).to eq("Bearer EAAG-token-secreto")
      expect(json_body(request)).to eq(
        "messaging_product" => "whatsapp", "recipient_type" => "individual", "to" => "5511991023344", "type" => "text",
        "text" => { "body" => "Confirmando: terça às 10h.", "preview_url" => false }, "context" => { "message_id" => "wamid.CITADA" }
      )
      expect(result).to have_attributes(wa_message_id: "wamid.ENVIADA1", wa_id: "5511991023344", bsuid: nil)
    end

    it "envia pelo BSUID quando a conversa não tem telefone" do
      requests = stub_graph(graph_response(200, { "contacts" => [ { "input" => "BR.118034776612", "user_id" => "BR.118034776612" } ],
                                                  "messages" => [ { "id" => "wamid.BSUID" } ] }))
      conversation = build(:whatsapp_conversation, wa_id: nil, bsuid: "BR.118034776612")
      result = client.send_text(conversation, "Oi, Lu!")

      expect(json_body(requests.first)).to include("recipient" => "BR.118034776612").and(satisfy { |body| !body.key?("to") })
      expect(result).to have_attributes(wa_message_id: "wamid.BSUID", bsuid: "BR.118034776612", wa_id: nil)
    end

    it "envia mídia já enviada, com legenda e nome do documento só onde a Meta aceita" do
      requests = stub_graph(sent, sent)
      client.send_media({ to: "5511991023344" }, type: "document", media_id: "1376223850470843", caption: "Escopo", filename: "escopo.pdf")
      client.send_media({ to: "5511991023344" }, type: "audio", media_id: "998877", caption: "ignorada", filename: "ignorado.ogg")

      expect(json_body(requests.first)["document"]).to eq("id" => "1376223850470843", "caption" => "Escopo", "filename" => "escopo.pdf")
      expect(json_body(requests.last)["audio"]).to eq("id" => "998877")
      expect { client.send_media({ to: "1" }, type: "pdf", media_id: "1") }.to raise_error(ArgumentError)
      expect { client.send_media({ to: "1" }, type: "image") }.to raise_error(ArgumentError)
    end

    it "envia template com corpo, cabeçalho de documento e botão de URL" do
      requests = stub_graph(sent)
      components = Whatsapp::TemplateComponents.build(
        header: { document: { id: "55", filename: "proposta.pdf" } },
        body: [ "Beatriz", "Novo site institucional", "20/09/2026" ],
        url_buttons: { 0 => "Gonçalves/P-029" }
      )
      client.send_template({ recipient: "BR.1" }, name: "lembrete_proposta", language: "pt_BR", components: components)

      expect(json_body(requests.first)["template"]).to eq(
        "name" => "lembrete_proposta", "language" => { "code" => "pt_BR" },
        "components" => [
          { "type" => "header", "parameters" => [ { "type" => "document", "document" => { "id" => "55", "filename" => "proposta.pdf" } } ] },
          { "type" => "body", "parameters" => [ { "type" => "text", "text" => "Beatriz" }, { "type" => "text", "text" => "Novo site institucional" },
                                                { "type" => "text", "text" => "20/09/2026" } ] },
          { "type" => "button", "sub_type" => "url", "index" => "0", "parameters" => [ { "type" => "text", "text" => "Gon%C3%A7alves/P-029" } ] }
        ]
      )
    end

    it "codifica o sufixo do botão de URL por segmento, mantendo as barras" do
      suffixes = Whatsapp::TemplateComponents.build(url_buttons: { 0 => "p/P-2026-029", 1 => "p/a b?c#d/", 2 => "AbC123_-.~" })
                                             .map { |c| c[:parameters].first[:text] }
      expect(suffixes).to eq([ "p/P-2026-029", "p/a%20b%3Fc%23d/", "AbC123_-.~" ])
    end

    it "monta parâmetros nomeados e cabeçalho de texto" do
      components = Whatsapp::TemplateComponents.build(header: [ "P-2026-029" ], body: { nome: "Beatriz" })
      expect(components).to eq([
        { type: "header", parameters: [ { type: "text", text: "P-2026-029" } ] },
        { type: "body", parameters: [ { type: "text", parameter_name: "nome", text: "Beatriz" } ] }
      ])
    end

    it "marca a mensagem recebida como lida" do
      requests = stub_graph(graph_response(200, { "success" => true }))
      expect(client.mark_as_read("wamid.RECEBIDA")).to be(true)
      expect(json_body(requests.first)).to eq("messaging_product" => "whatsapp", "status" => "read", "message_id" => "wamid.RECEBIDA")
    end
  end

  describe "mídia" do
    it "faz upload em multipart e devolve o ID" do
      requests = stub_graph(graph_response(200, { "id" => "1037543291543636" }))
      id = client.upload_media(StringIO.new("%PDF"), filename: "escopo.pdf", mime_type: "application/pdf")
      expect(id).to eq("1037543291543636")
      expect(requests.first.path).to eq("/v26.0/6655443322110099/media")
      expect(requests.first.content_type).to eq("multipart/form-data")
    end

    it "baixa a mídia pela URL temporária, com o token, e confere o sha256" do
      content = "conteúdo-da-imagem"
      requests = stub_graph(
        graph_response(200, { "url" => "https://lookaside.fbsbx.com/whatsapp_business/attachments/?mid=1", "mime_type" => "image/jpeg",
                              "sha256" => Digest::SHA256.hexdigest(content), "file_size" => content.bytesize, "id" => "1234" }),
        graph_response(200, content)
      )
      media = client.download_media("1234")

      expect(requests.first.path).to eq("/v26.0/1234?phone_number_id=6655443322110099")
      expect(requests.last.uri.host).to eq("lookaside.fbsbx.com")
      expect(requests.last["Authorization"]).to eq("Bearer EAAG-token-secreto")
      expect(media.file.read).to eq(content.b)
      expect(media).to have_attributes(mime_type: "image/jpeg", size: content.bytesize)
      media.file.close!
    end

    it "recusa a mídia que não confere com o sha256" do
      stub_graph(graph_response(200, { "url" => "https://lookaside.fbsbx.com/m", "mime_type" => "image/jpeg", "sha256" => "abc" }),
                 graph_response(200, "outro conteúdo"))
      expect { client.download_media("1234") }.to raise_error(Whatsapp::Error, /sha256/)
    end

    it "recusa antes de baixar a mídia que a Meta informa acima do limite do tipo" do
      allow(Rails.logger).to receive(:warn)
      requests = stub_graph(graph_response(200, { "url" => "https://lookaside.fbsbx.com/m", "mime_type" => "image/jpeg", "file_size" => "7340032" }))
      expect { client.download_media("1234") }.to raise_error(Whatsapp::Error, "A mídia tem 7 MB e passa do limite de 5 MB para imagem.") { |e|
        expect(e).not_to be_transient
      }
      expect(requests.size).to eq(1)
      expect(Rails.logger).to have_received(:warn).with(a_string_including("[Whatsapp] GET /m: A mídia tem 7 MB"))
    end

    it "interrompe o download que passa do limite mesmo sem o tamanho informado e apaga o arquivo" do
      chunk = "x" * 300.kilobytes
      download = graph_response(200, "")
      allow(download).to receive(:read_body).and_yield(chunk).and_yield(chunk).and_yield(chunk)
      stub_graph(graph_response(200, { "url" => "https://lookaside.fbsbx.com/m", "mime_type" => "image/webp" }), download)
      files = []
      allow(Tempfile).to receive(:new).and_wrap_original { |original, *args, **options| original.call(*args, **options).tap { |f| files << f } }

      expect { client.download_media("1234") }.to raise_error(Whatsapp::Error, "A mídia passou do limite de 500 KB para figurinha durante o download.")
      expect(files.first.path).to be_nil # close! apagou o arquivo
    end

    it "deduz o tipo da mídia pelo mime_type" do
      types = [ "image/jpeg", "image/webp", "audio/ogg; codecs=opus", "video/mp4", "application/pdf", nil ].map { |m| described_class.media_type(m) }
      expect(types).to eq(%w[image sticker audio video document document])
    end
  end

  describe "templates" do
    it "lista todas as páginas, pedindo os campos necessários" do
      requests = stub_graph(
        graph_response(200, { "data" => [ { "name" => "a" } ], "paging" => { "cursors" => { "after" => "CURSOR2" }, "next" => "https://graph.facebook.com/..." } }),
        graph_response(200, { "data" => [ { "name" => "b" } ], "paging" => { "cursors" => { "after" => "CURSOR3" } } })
      )
      expect(client.templates.map { |t| t["name"] }).to eq(%w[a b])
      first, second = requests.map { |r| Rack::Utils.parse_query(r.uri.query) }
      expect(requests.first.uri.path).to eq("/v26.0/1029384756102938/message_templates")
      expect(first["fields"]).to eq("id,name,language,category,status,components,parameter_format,rejected_reason")
      expect(first).not_to have_key("after")
      expect(second["after"]).to eq("CURSOR2")
    end

    it "cria com a categoria em maiúsculas, edita e apaga um idioma" do
      requests = stub_graph(graph_response(200, { "id" => "594425", "status" => "PENDING", "category" => "UTILITY" }),
                            graph_response(200, { "success" => true }), graph_response(200, { "success" => true }))
      body = [ { "type" => "BODY", "text" => "Olá, {{1}}.", "example" => { "body_text" => [ [ "Beatriz" ] ] } } ]
      created = client.create_template(name: "lembrete_proposta", language: "pt_BR", category: "utility", components: body)
      client.update_template("594425", components: body)
      client.delete_template(name: "lembrete_proposta", meta_template_id: "594425")

      expect(created).to eq("id" => "594425", "status" => "PENDING", "category" => "UTILITY")
      expect(json_body(requests[0])).to include("name" => "lembrete_proposta", "language" => "pt_BR", "category" => "UTILITY", "allow_category_change" => false)
      expect(requests[1].path).to eq("/v26.0/594425")
      expect(requests[2].method).to eq("DELETE")
      expect(requests[2].path).to eq("/v26.0/1029384756102938/message_templates?name=lembrete_proposta&hsm_id=594425")
    end

    it "converte categoria, status e motivo da Meta para os enums" do
      attrs = WhatsappTemplate.attributes_from_meta({
        "id" => "594425", "name" => "lembrete_proposta", "language" => "pt_BR", "category" => "UTILITY",
        "status" => "PENDING_DELETION", "rejected_reason" => "NONE", "components" => [ { "type" => "BODY", "text" => "Olá, {{1}}." } ]
      })
      expect(attrs).to include(meta_template_id: "594425", category: "utility", status: "pending_deletion")
      expect(attrs).not_to have_key(:rejection_reason)
      template = create(:whatsapp_template, **attrs)
      expect(template.status_label).to eq("Excluindo")
      expect(WhatsappTemplate.attributes_from_meta({ "status" => "REJECTED", "rejected_reason" => "INCORRECT_CATEGORY" })[:rejection_reason]).to eq("INCORRECT_CATEGORY")
    end

    it "troca categoria e status desconhecidos por um padrão seguro, com aviso no log" do
      allow(Rails.logger).to receive(:warn)
      data = { "id" => "594426", "name" => "boas_vindas", "language" => "pt_BR", "category" => "NOVA_CATEGORIA", "status" => "EM_REVISAO_ESPECIAL",
               "components" => [ { "type" => "BODY", "text" => "Olá!" } ] }

      attrs = WhatsappTemplate.attributes_from_meta(data)
      expect(attrs).to include(category: "utility", status: "pending")
      expect(create(:whatsapp_template, **attrs)).to be_persisted
      expect(Rails.logger).to have_received(:warn).with("[Whatsapp] valor desconhecido: category=NOVA_CATEGORIA, template=boas_vindas")
      expect(Rails.logger).to have_received(:warn).with("[Whatsapp] valor desconhecido: status=EM_REVISAO_ESPECIAL, template=boas_vindas")

      current = build(:whatsapp_template, category: "marketing")
      expect(WhatsappTemplate.attributes_from_meta(data, current: current)).to include(category: "marketing", status: "pending")
      expect(WhatsappTemplate.attributes_from_meta(data.except("category", "status"))).not_to include(:category, :status)
    end
  end

  describe "falhas de rede" do
    it "separa o pedido que não saiu do que pode ter sido processado pela Meta" do
      not_sent = [ Net::OpenTimeout, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError, OpenSSL::SSL::SSLError ]
      uncertain = [ Net::ReadTimeout, Errno::ECONNRESET, EOFError, Net::HTTPBadResponse ]
      (not_sent + uncertain).each do |exception|
        stub_graph(exception)
        error = begin
          client.mark_as_read("wamid.1")
        rescue Whatsapp::Error => e
          e
        end
        expect(error).to be_a(Whatsapp::Error).and(be_transient)
        expect(error.delivery_uncertain?).to eq(uncertain.include?(exception)), "#{exception}: #{error.delivery_uncertain?}"
      end
      expect(Whatsapp::Error.new("x")).not_to be_delivery_uncertain
    end
  end

  describe "exemplo de mídia do template" do
    let(:session_id) { "upload:MTphdHRhY2htZW50OjZiMmE3NDZk?sig=ARZtiC6xXUe8D4V8YmM" }

    it "abre a sessão de upload do app e envia o arquivo, devolvendo o handle" do
      requests = stub_graph(graph_response(200, { "id" => session_id }), graph_response(200, { "h" => "4::aW1hZ2UvanBlZw==:ARZ" }))

      handle = client.upload_template_sample(StringIO.new("%PDF-1.7 proposta"), filename: "proposta.pdf", mime_type: "application/pdf")

      expect(handle).to eq("4::aW1hZ2UvanBlZw==:ARZ")
      open, upload = requests
      expect(open.method).to eq("POST")
      expect(open.uri.path).to eq("/v26.0/app-de-teste/uploads")
      expect(Rack::Utils.parse_query(open.uri.query)).to eq("file_name" => "proposta.pdf", "file_length" => "17", "file_type" => "application/pdf")
      expect(open["Authorization"]).to eq("Bearer EAAG-token-secreto")
      expect(upload.path).to eq("/v26.0/#{session_id}")
      expect(upload["Authorization"]).to eq("OAuth EAAG-token-secreto")
      expect(upload["file_offset"]).to eq("0")
      expect(upload.body).to eq("%PDF-1.7 proposta")
    end

    it "recusa o arquivo acima do limite do tipo antes de chamar a Meta" do
      stub_graph
      big = StringIO.new("x" * (5.megabytes + 1))
      expect { client.upload_template_sample(big, filename: "foto.jpg", mime_type: "image/jpeg") }
        .to raise_error(Whatsapp::Error, "A mídia tem 5 MB e passa do limite de 5 MB para imagem.")
    end
  end

  describe "conta" do
    it "inscreve o app na WABA e lê os dados do número" do
      requests = stub_graph(graph_response(200, { "success" => true }),
                            graph_response(200, { "display_phone_number" => "+55 11 97070-2026", "verified_name" => "DevBatista", "quality_rating" => "GREEN",
                                                  "whatsapp_business_manager_messaging_limit" => "TIER_250", "is_on_biz_app" => true, "id" => "6655443322110099" }))
      expect(client.subscribe_app).to be(true)
      details = client.phone_number_details

      expect(requests.first.path).to eq("/v26.0/1029384756102938/subscribed_apps")
      expect(Rack::Utils.parse_query(requests.last.uri.query)["fields"]).to include("whatsapp_business_manager_messaging_limit", "is_on_biz_app")
      expect(WhatsappAccount.attributes_from_phone_details(details)).to eq(
        display_phone_number: "+55 11 97070-2026", verified_name: "DevBatista", quality_rating: "green",
        messaging_limit_tier: "TIER_250", coexistence: true
      )
      expect(WhatsappAccount.attributes_from_phone_details("quality_rating" => "NA")[:quality_rating]).to eq("unknown")
    end

    it "pede a sincronização da coexistência e explica quando ela já foi feita" do
      requests = stub_graph(graph_response(200, { "messaging_product" => "whatsapp", "request_id" => "REQ-1" }),
                            graph_error(400, 2_593_107, "You have exceeded the maximum number of times to call the synchronization api"))
      expect(client.request_sync(:contacts)).to eq("REQ-1")
      expect(json_body(requests.first)).to eq("messaging_product" => "whatsapp", "sync_type" => "smb_app_state_sync")
      expect { client.request_sync(:history) }.to raise_error(Whatsapp::Error) { |e|
        expect(e.user_message).to eq("A sincronização com o app do celular já foi feita para este número.")
        expect(e).not_to be_transient
      }
      expect { client.request_sync(:tudo) }.to raise_error(KeyError)
    end

    it "registra o número sem coexistência com o PIN de 6 dígitos" do
      requests = stub_graph(graph_response(200, { "success" => true }))
      expect(client.register(pin: "212834")).to be(true)
      expect(requests.first.path).to eq("/v26.0/6655443322110099/register")
      expect(json_body(requests.first)).to eq("messaging_product" => "whatsapp", "pin" => "212834")
      expect { client.register(pin: "1234") }.to raise_error(ArgumentError)
      expect { client.register(pin: nil) }.to raise_error(ArgumentError)
    end

    it "troca o code do Embedded Signup pelo token, sem cabeçalho de autorização" do
      requests = stub_graph(graph_response(200, { "access_token" => "EAAG-novo-token", "token_type" => "bearer" }))
      expect(described_class.exchange_code("CODE-30S")).to eq("EAAG-novo-token")
      expect(requests.first.path).to start_with("/v26.0/oauth/access_token?")
      expect(Rack::Utils.parse_query(requests.first.uri.query)).to eq("client_id" => "app-de-teste", "client_secret" => "segredo-de-teste", "code" => "CODE-30S")
      expect(requests.first["Authorization"]).to be_nil
    end

    it "não troca o code sem o app configurado" do
      allow(Whatsapp.config).to receive(:app_secret).and_return(nil)
      expect { described_class.exchange_code("CODE") }.to raise_error(Whatsapp::Error, /META_APP_SECRET/)
    end
  end

  describe "erros" do
    it "separa o erro da Meta e diz o que fazer" do
      stub_graph(graph_error(400, 131_047, "(#131047) Re-engagement message", details: "More than 24 hours have passed"))
      expect { client.send_text({ to: "5511991023344" }, "Oi") }.to raise_error(Whatsapp::Error) { |e|
        expect(e).to have_attributes(code: 131_047, details: "More than 24 hours have passed", fbtrace_id: "AbCdEf123", http_status: 400)
        expect(e).to be_window_closed
        expect(e).not_to be_transient
        expect(e.user_message).to eq("A janela de 24h está fechada. Envie um template aprovado.")
      }
    end

    it "marca como transitórios o limite de envio, o erro do servidor e a falha de rede" do
      stub_graph(graph_error(429, 130_429, "(#130429) Rate limit hit"), graph_response(502, "<html>Bad Gateway</html>"))
      expect { client.mark_as_read("wamid.1") }.to raise_error(Whatsapp::Error) { |e| expect(e).to be_rate_limited.and be_transient }
      expect { client.mark_as_read("wamid.1") }.to raise_error(Whatsapp::Error) { |e| expect(e).to have_attributes(message: "HTTP 502", transient?: true) }

      allow(Net::HTTP).to receive(:start).and_raise(Net::OpenTimeout)
      expect { client.mark_as_read("wamid.1") }.to raise_error(Whatsapp::Error) { |e| expect(e).to be_network.and be_transient }
    end

    it "explica os bloqueios da conta e do número sem marcar para tentar de novo logo" do
      expectations = {
        131_042 => /forma de pagamento/, 131_048 => /limite de envio.*spam/, 131_049 => /marketing.*24h/,
        131_031 => /bloqueada pela Meta/, 133_010 => /não está registrado/, 368 => /bloqueada temporariamente/
      }
      stub_graph(*expectations.keys.map { |code| graph_error(400, code, "(##{code}) erro", transient: true) })
      expectations.each do |code, text|
        expect { client.send_text({ to: "5511991023344" }, "Oi") }.to raise_error(Whatsapp::Error) { |e|
          expect(e.code).to eq(code)
          expect(e.user_message).to match(text)
          expect(e).not_to be_transient
        }
      end
    end

    it "reconhece o token expirado" do
      stub_graph(graph_error(401, 190, "Error validating access token"))
      expect { client.subscribed_apps }.to raise_error(Whatsapp::Error) { |e| expect(e).to be_token_invalid }
    end

    it "não expõe o token no log nem no inspect" do
      allow(Rails.logger).to receive(:warn)
      stub_graph(graph_error(400, 100, "Invalid parameter"))
      expect { client.phone_number_details }.to raise_error(Whatsapp::Error)
      expect(Rails.logger).to have_received(:warn).with(a_string_including("GET /v26.0/6655443322110099", "code=100").and(satisfy { |line| !line.include?("EAAG-token-secreto") }))
      expect(client.inspect).not_to include("EAAG-token-secreto")
    end
  end
end
