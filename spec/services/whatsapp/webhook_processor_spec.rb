require "rails_helper"

RSpec.describe Whatsapp::WebhookProcessor do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:account) { create(:whatsapp_account) }
  let(:at) { Time.zone.parse("2026-10-27 10:00") }
  let(:phone) { WhatsappWebhookHelpers::CONTACT_PHONE }
  let(:bsuid) { WhatsappWebhookHelpers::CONTACT_BSUID }

  before { travel_to Time.zone.parse("2026-10-27 12:00") }

  describe "mensagens recebidas" do
    it "cria a conversa com BSUID, telefone e nome, grava a mensagem e abre a janela" do
      process_webhook(account, "messages", contacts: [ wa_contact(username: "@henrique") ],
                                           messages: [ wa_message("wamid.IN1", "Bom dia!", context: { from: phone, id: "wamid.CITADA" }) ])

      conversation = account.conversations.sole
      expect(conversation).to have_attributes(bsuid: bsuid, wa_id: phone, profile_name: "Henrique Duarte", username: "@henrique",
                                              unread_count: 1, preview: "Bom dia!", last_inbound_at: at, last_message_at: at)
      expect(conversation).to be_window_open
      expect(conversation.messages.sole).to have_attributes(
        wa_message_id: "wamid.IN1", direction: "inbound", origin: "contact", status: "received", kind: "text", body: "Bom dia!",
        reply_to_wa_message_id: "wamid.CITADA", sent_at: at, from_history: false
      )
      expect(account.reload.last_webhook_at).to eq(Time.current)
    end

    it "é idempotente, inclusive quando outro job grava a mesma mensagem ao mesmo tempo" do
      2.times { process_webhook(account, "messages", contacts: [ wa_contact ], messages: [ wa_message("wamid.IN1", "Oi") ]) }
      allow(WhatsappMessage).to receive(:exists?).and_return(false) # a checagem não viu a gravação do outro job
      process_webhook(account, "messages", contacts: [ wa_contact ], messages: [ wa_message("wamid.IN1", "Oi") ])

      expect(WhatsappMessage.count).to eq(1)
      expect(account.conversations.sole.unread_count).to eq(1)
    end

    it "aceita quem só tem BSUID (sem telefone) e completa o BSUID da conversa iniciada pelo telefone" do
      process_webhook(account, "messages", contacts: [ wa_contact(wa_id: nil, user_id: "BR.999", name: "Lu") ],
                                           messages: [ wa_message("wamid.U1", "Oi", from: nil, from_user_id: "BR.999") ])
      expect(account.conversations.find_by(bsuid: "BR.999")).to have_attributes(wa_id: nil, display_name: "Lu")

      by_phone = create(:whatsapp_conversation, account: account, bsuid: nil, wa_id: phone)
      process_webhook(account, "messages", contacts: [ wa_contact ], messages: [ wa_message("wamid.P1", "Respondendo") ])
      expect(by_phone.reload).to have_attributes(bsuid: bsuid, unread_count: 1)
      expect(account.conversations.count).to eq(2)
    end

    it "junta a conversa do BSUID com a do telefone quando a Meta mostra que são a mesma pessoa" do
      lead = create(:lead)
      by_bsuid = create(:whatsapp_conversation, account: account, bsuid: bsuid, wa_id: nil, unread_count: 2)
      by_phone = create(:whatsapp_conversation, account: account, bsuid: nil, wa_id: phone, lead: lead, unread_count: 1)
      old = create(:whatsapp_message, conversation: by_phone, sent_at: at - 1.day)

      process_webhook(account, "messages", contacts: [ wa_contact ], messages: [ wa_message("wamid.M1", "Oi") ])

      expect { by_phone.reload }.to raise_error(ActiveRecord::RecordNotFound)
      expect(by_bsuid.reload).to have_attributes(wa_id: phone, lead_id: lead.id, unread_count: 4)
      expect(by_bsuid.messages.map(&:wa_message_id)).to eq([ old.wa_message_id, "wamid.M1" ])
    end

    it "tira o telefone da conversa antiga quando ele passa a outra pessoa (outro BSUID)" do
      previous_owner = create(:whatsapp_conversation, account: account, bsuid: "BR.ANTIGO", wa_id: phone)
      process_webhook(account, "messages", contacts: [ wa_contact ], messages: [ wa_message("wamid.N1", "Oi") ])

      expect(previous_owner.reload).to have_attributes(bsuid: "BR.ANTIGO", wa_id: nil)
      expect(account.conversations.find_by(bsuid: bsuid)).to have_attributes(wa_id: phone)
    end

    # O outro job não dá para simular dentro da transação do teste (o rollback do savepoint o
    # desfaria); o teste garante a nova tentativa depois do RecordNotUnique.
    it "tenta de novo quando esbarra no índice único (outro job criou a mesma conversa)" do
      saves = 0
      allow_any_instance_of(WhatsappConversation).to receive(:save!).and_wrap_original do |original, *args|
        saves += 1
        raise ActiveRecord::RecordNotUnique, "duplicate key value violates unique constraint" if saves == 1

        original.call(*args)
      end

      process_webhook(account, "messages", contacts: [ wa_contact ], messages: [ wa_message("wamid.R1", "Oi") ])
      expect(WhatsappConversation.sole.messages.sole.wa_message_id).to eq("wamid.R1")
      expect(saves).to eq(3) # a tentativa que esbarrou, a que criou e a atualização da prévia
    end

    it "grava mídia, localização, contato e resposta de botão, e baixa a mídia num job" do
      process_webhook(account, "messages", contacts: [ wa_contact ], messages: [
        wa_message("wamid.D1", type: "document", document: { id: "1376223850470843", mime_type: "application/pdf", sha256: "x",
                                                               filename: "escopo.pdf", caption: "Escopo" }),
        wa_message("wamid.L1", type: "location", location: { latitude: -23.56, longitude: -46.65, name: "Escritório" }),
        wa_message("wamid.C1", type: "contacts", contacts: [ { name: { formatted_name: "Barbara Johnson" }, phones: [ { phone: "+55 11 5555-0829" } ] } ]),
        wa_message("wamid.B1", type: "button", button: { text: "Quero agendar", payload: "agendar" }),
        wa_message("wamid.X1", type: "order", order: { catalog_id: "1" })
      ])

      messages = account.conversations.sole.messages.index_by(&:wa_message_id)
      expect(messages["wamid.D1"]).to have_attributes(kind: "document", media_id: "1376223850470843", media_mime_type: "application/pdf",
                                                      media_filename: "escopo.pdf", body: "Escopo")
      expect(messages["wamid.L1"]).to have_attributes(kind: "location", body: "Escritório · -23.56, -46.65")
      expect(messages["wamid.C1"]).to have_attributes(kind: "contacts", body: "Barbara Johnson (+55 11 5555-0829)")
      expect(messages["wamid.B1"]).to have_attributes(kind: "button", body: "Quero agendar")
      expect(messages["wamid.X1"]).to have_attributes(kind: "unsupported", body: nil)
      expect(WhatsappMediaJob).to have_been_enqueued.with(messages["wamid.D1"]).exactly(:once)
    end

    it "mantém só a reação mais nova da pessoa sobre a mensagem, sem contar como não lida" do
      conversation = create(:whatsapp_conversation, account: account, bsuid: bsuid, wa_id: phone)
      target = create(:whatsapp_message, :outbound, conversation: conversation, sent_at: at - 1.hour)
      conversation.update!(last_message_at: target.sent_at, preview: "Proposta enviada")
      react = ->(id, emoji, time) { process_webhook(account, "messages", contacts: [ wa_contact ], messages: [ wa_message(id, type: "reaction", at: time, reaction: { message_id: target.wa_message_id, emoji: emoji }) ]) }

      react.call("wamid.R1", "👍", at)
      react.call("wamid.R2", "❤️", at + 1.minute)
      expect(target.reactions.reload.map(&:reaction_emoji)).to eq([ "❤️" ])
      react.call("wamid.R3", "", at + 2.minutes) # removeu a reação
      react.call("wamid.R1-reenvio", "👍", at) # reenvio atrasado da primeira
      expect(target.reactions.reload.map(&:reaction_emoji)).to eq([ "" ])
      expect(conversation.reload).to have_attributes(unread_count: 0, preview: "Proposta enviada", last_inbound_at: nil)
    end

    it "troca o BSUID e o telefone da conversa nas mensagens de sistema, sem contar como não lida" do
      conversation = create(:whatsapp_conversation, account: account, bsuid: "BR.ANTIGO", wa_id: phone)
      process_webhook(account, "messages", messages: [ { id: "wamid.S1", timestamp: at.to_i.to_s, type: "system",
                                                         system: { body: "User changed from BR.ANTIGO to BR.NOVO", type: "user_changed_user_id",
                                                                   user_id: "BR.NOVO", previous_user_id: "BR.ANTIGO" } } ])
      expect(conversation.reload).to have_attributes(bsuid: "BR.NOVO", wa_id: phone, unread_count: 0)

      process_webhook(account, "messages", messages: [ { from: phone, id: "wamid.S2", timestamp: at.to_i.to_s, type: "system",
                                                         system: { body: "User changed from #{phone} to 5511988887777", wa_id: "5511988887777",
                                                                   type: "user_changed_number", user_id: "BR.NOVO" } } ])
      expect(conversation.reload).to have_attributes(bsuid: "BR.NOVO", wa_id: "5511988887777", unread_count: 0, last_inbound_at: nil)
      expect(conversation.messages.map(&:kind)).to eq(%w[system system])
      expect(account.conversations.count).to eq(1)
    end

    it "ignora request_welcome, mensagem sem remetente e conta que não está no Admin" do
      process_webhook(account, "messages", messages: [ wa_message("wamid.W1", type: "request_welcome"), wa_message("wamid.W2", "Oi", from: nil, from_user_id: nil) ])
      expect(WhatsappMessage.count).to eq(0)

      other = build(:whatsapp_account)
      expect { process_webhook(other, "messages", contacts: [ wa_contact ], messages: [ wa_message("wamid.W3", "Oi") ]) }.not_to raise_error
      expect(WhatsappConversation.count).to eq(0)
    end
  end

  describe "status das mensagens enviadas" do
    let(:conversation) { create(:whatsapp_conversation, account: account, bsuid: nil, wa_id: phone) }
    let!(:sent) { create(:whatsapp_message, :outbound, conversation: conversation, wa_message_id: "wamid.OUT1", status: "pending", sent_at: at) }

    it "só avança o status, mesmo fora de ordem, e completa o BSUID da conversa" do
      process_webhook(account, "messages", statuses: [ wa_status("wamid.OUT1", "read", at: at + 5.minutes, recipient_user_id: bsuid) ])
      process_webhook(account, "messages", statuses: [ wa_status("wamid.OUT1", "delivered", at: at + 1.minute), wa_status("wamid.OUT1", "sent", at: at) ])

      expect(sent.reload).to have_attributes(status: "read", read_at: at + 5.minutes, delivered_at: at + 5.minutes)
      expect(conversation.reload.bsuid).to eq(bsuid)
    end

    it "relê o status com a mensagem travada, sem sobrescrever o que outro job gravou ao mesmo tempo" do
      # Os dois webhooks carregaram a mensagem ainda "Enviando"; antes de gravarem, outro job gravou "Lida".
      stale_delivered = WhatsappMessage.find(sent.id)
      stale_failed = WhatsappMessage.find(sent.id)
      sent.update!(status: "read", delivered_at: at + 1.minute, read_at: at + 2.minutes)
      relation = WhatsappMessage.joins(:conversation)
      allow(WhatsappMessage).to receive(:joins).and_return(relation)
      allow(relation).to receive(:find_by).and_return(stale_delivered, stale_failed)
      [ stale_delivered, stale_failed ].each { |message| allow(message).to receive(:with_lock).and_call_original }

      process_webhook(account, "messages", statuses: [ wa_status("wamid.OUT1", "delivered", at: at + 1.minute),
                                                       wa_status("wamid.OUT1", "failed", errors: [ { code: 131_026, title: "Message undeliverable" } ]) ])

      expect(sent.reload).to have_attributes(status: "read", read_at: at + 2.minutes, error_code: nil)
      expect(stale_delivered).to have_received(:with_lock)
      expect(stale_failed).to have_received(:with_lock)
    end

    it "marca a falha com o código e a mensagem em português" do
      process_webhook(account, "messages", statuses: [
        wa_status("wamid.OUT1", "failed", errors: [ { code: 131_049, title: "This message was not delivered to maintain healthy ecosystem engagement.",
                                                      error_data: { details: "In order to maintain a healthy ecosystem engagement..." } } ])
      ])
      expect(sent.reload).to have_attributes(status: "failed", error_code: "131049", error_message: a_string_including("marketing"))
    end

    it "tenta de novo quando o status chega antes de a mensagem ser gravada, e desiste depois" do
      value = { messaging_product: "whatsapp", metadata: { phone_number_id: account.phone_number_id },
                statuses: [ wa_status("wamid.AINDA-NAO", "sent"), wa_status("wamid.OUT1", "delivered") ] }.deep_stringify_keys
      expect { process_change("messages", value, entry_id: account.waba_id) }.to raise_error(described_class::StatusTargetMissing, /wamid.AINDA-NAO/)
      expect(sent.reload.status).to eq("delivered") # o resto foi processado

      expect { WhatsappWebhookJob.perform_now(account.waba_id, "messages", value) }.to have_enqueued_job(WhatsappWebhookJob)
    end
  end

  describe "ecos do app do celular" do
    it "grava a mensagem enviada pelo celular, zera as não lidas e não abre a janela" do
      conversation = create(:whatsapp_conversation, account: account, bsuid: nil, wa_id: phone, unread_count: 3)
      process_webhook(account, "smb_message_echoes", message_echoes: [
        { from: WhatsappWebhookHelpers::BUSINESS_PHONE, to: "+#{phone}", id: "wamid.ECO1", timestamp: at.to_i.to_s, type: "text", text: { body: "Te ligo já" } }
      ])

      expect(conversation.reload).to have_attributes(unread_count: 0, preview: "Te ligo já", last_inbound_at: nil)
      expect(conversation.messages.sole).to have_attributes(direction: "outbound", origin: "phone", status: "sent", body: "Te ligo já")
    end

    it "aplica edição e exclusão na mensagem original" do
      conversation = create(:whatsapp_conversation, account: account, bsuid: nil, wa_id: phone)
      original = create(:whatsapp_message, conversation: conversation, direction: "outbound", origin: "phone", status: "sent", wa_message_id: "wamid.ORIG", body: "Valor: R$ 1.000", sent_at: at)
      echo = ->(id, type, content) { process_webhook(account, "smb_message_echoes", message_echoes: [ { from: WhatsappWebhookHelpers::BUSINESS_PHONE, to: phone, id: id, timestamp: (at + 2.minutes).to_i.to_s, type: type, type => content } ]) }

      echo.call("wamid.EDIT", "edit", { original_message_id: "wamid.ORIG", message: { type: "text", text: { body: "Valor: R$ 1.200" } } })
      expect(original.reload).to have_attributes(body: "Valor: R$ 1.200", edited_at: at + 2.minutes)
      echo.call("wamid.REVOKE", "revoke", { original_message_id: "wamid.ORIG" })
      expect(original.reload.revoked_at).to eq(at + 2.minutes)
      expect(WhatsappMessage.count).to eq(1)
    end
  end

  describe "histórico do celular" do
    let(:chunk) do
      { metadata: { phase: 0, chunk_order: 1, progress: 55 }, threads: [ { id: phone, messages: [
        { from: WhatsappWebhookHelpers::BUSINESS_PHONE, id: "wamid.H1", timestamp: (at - 2.days).to_i.to_s, type: "text", text: { body: "Segue a proposta" }, history_context: { status: "READ" } },
        { from: WhatsappWebhookHelpers::BUSINESS_PHONE, id: "wamid.H2", timestamp: (at - 2.days + 1.minute).to_i.to_s, type: "media_placeholder", history_context: { status: "DELIVERED" } },
        { from: phone, id: "wamid.H3", timestamp: (at - 1.day).to_i.to_s, type: "text", text: { body: "Obrigado!" }, history_context: { status: "READ" } }
      ] } ] }
    end

    it "grava as mensagens antigas sem abrir a janela nem contar como não lidas, e acompanha o progresso" do
      2.times { process_webhook(account, "history", history: [ chunk ]) }

      conversation = account.conversations.sole
      expect(conversation).to have_attributes(wa_id: phone, unread_count: 0, last_inbound_at: nil, last_message_at: at - 1.day, preview: "Obrigado!")
      expect(conversation.messages.map { |m| [ m.wa_message_id, m.direction, m.origin, m.status, m.from_history ] }).to eq([
        [ "wamid.H1", "outbound", "phone", "read", true ], [ "wamid.H2", "outbound", "phone", "delivered", true ], [ "wamid.H3", "inbound", "contact", "received", true ]
      ])
      expect(account.reload).to have_attributes(history_sync_progress: 55, history_synced_at: nil)

      process_webhook(account, "history", history: [ chunk.deep_merge(metadata: { chunk_order: 2, progress: 100 }, threads: []) ])
      expect(account.reload).to have_attributes(history_sync_progress: 100, history_synced_at: Time.current)
    end

    it "completa a mídia que veio como placeholder e registra a recusa do compartilhamento" do
      process_webhook(account, "history", history: [ chunk ])
      process_webhook(account, "history", messages: [ { from: WhatsappWebhookHelpers::BUSINESS_PHONE, id: "wamid.H2", timestamp: (at - 2.days + 1.minute).to_i.to_s,
                                                        type: "image", image: { mime_type: "image/jpeg", sha256: "x", id: "2423079", caption: "Fachada" } } ])
      placeholder = WhatsappMessage.find_by(wa_message_id: "wamid.H2")
      expect(placeholder).to have_attributes(kind: "image", media_id: "2423079", body: "Fachada", status: "delivered")
      expect(WhatsappMediaJob).to have_been_enqueued.with(placeholder)

      process_webhook(account, "history", history: [ { errors: [ { code: 2_593_109, title: "History sync is turned off by the business from the WhatsApp Business App",
                                                                   error_data: { details: "History sharing is turned off by the business" } } ] } ])
      expect(account.reload.history_sync_error).to eq("History sharing is turned off by the business")
    end
  end

  describe "agenda do celular" do
    it "guarda o nome salvo, que vira o nome da conversa, e apaga quando o contato sai da agenda" do
      existing = create(:whatsapp_conversation, account: account, bsuid: nil, wa_id: phone, profile_name: "Henrique")
      process_webhook(account, "smb_app_state_sync", state_sync: [
        { type: "contact", contact: { full_name: "Henrique Duarte (Duarte Engenharia)", first_name: "Henrique", phone_number: phone }, action: "add", metadata: { timestamp: at.to_i.to_s } },
        { type: "contact", contact: { full_name: "Pablo Morales", first_name: "Pablo", phone_number: "16505551234" }, action: "add", metadata: { timestamp: at.to_i.to_s } }
      ])

      expect(existing.reload.display_name).to eq("Henrique Duarte (Duarte Engenharia)")
      expect(account.conversations.find_by(wa_id: "16505551234").saved_name).to eq("Pablo Morales")
      expect(account.conversations.with_messages).to be_empty # sem mensagem, fora da caixa de entrada
      expect(account.reload.contacts_synced_at).to eq(Time.current)

      process_webhook(account, "smb_app_state_sync", state_sync: [ { type: "contact", contact: { phone_number: phone }, action: "remove", metadata: { timestamp: at.to_i.to_s } } ])
      expect(existing.reload.display_name).to eq("Henrique")
    end
  end

  describe "conta" do
    it "desconecta o número no PARTNER_REMOVED e mantém as conversas" do
      conversation = create(:whatsapp_conversation, account: account)
      process_change("account_update", { event: "PARTNER_REMOVED", waba_info: { waba_id: account.waba_id, owner_business_id: "232941" },
                                         disconnection_info: { reason: "ACCOUNT_DISCONNECTED", initiated_by: "USER" } },
                     entry_id: "2949482758682047", time: at.to_i)

      expect(account.reload).to have_attributes(status: "disconnected", disconnected_at: at, disconnect_reason: "PARTNER_REMOVED: ACCOUNT_DISCONNECTED")
      expect(conversation.reload).to be_persisted
      expect(AuditLog.where(auditable: account, action: "status_change")).to exist
    end

    it "reconecta depois do ACCOUNT_OFFBOARDED e só registra violações no log" do
      allow(Rails.logger).to receive(:warn)
      process_change("account_update", { event: "ACCOUNT_OFFBOARDED" }, entry_id: account.waba_id)
      expect(account.reload.status).to eq("disconnected")
      process_change("account_update", { event: "ACCOUNT_RECONNECTED" }, entry_id: account.waba_id)
      expect(account.reload).to have_attributes(status: "connected", disconnect_reason: nil)

      process_change("account_update", { event: "ACCOUNT_VIOLATION", violation_info: { violation_type: "SCAM" } }, entry_id: account.waba_id)
      expect(account.reload.status).to eq("connected")
      expect(Rails.logger).to have_received(:warn).with(a_string_including("ACCOUNT_VIOLATION", "SCAM"))
    end

    it "relê qualidade, nome e limite quando a Meta avisa mudança no número" do
      stub_graph(graph_response(200, { "display_phone_number" => "+55 11 97070-2026", "verified_name" => "DevBatista Tecnologia",
                                       "quality_rating" => "YELLOW", "whatsapp_business_manager_messaging_limit" => "TIER_2K" }),
                 graph_error(500, 1, "Unknown error"))
      process_change("phone_number_quality_update", { display_phone_number: WhatsappWebhookHelpers::BUSINESS_PHONE, event: "THROUGHPUT_UPGRADE", current_limit: "TIER_10K" },
                     entry_id: account.waba_id)
      expect(account.reload).to have_attributes(verified_name: "DevBatista Tecnologia", quality_rating: "yellow", messaging_limit_tier: "TIER_2K")

      process_change("phone_number_quality_update", { display_phone_number: WhatsappWebhookHelpers::BUSINESS_PHONE, current_limit: "TIER_10K" }, entry_id: account.waba_id)
      expect(account.reload.messaging_limit_tier).to eq("TIER_10K") # sem a Graph API, fica o limite do webhook
    end
  end

  describe "templates" do
    let!(:template) { create(:whatsapp_template, account: account, name: "order_confirmation", language: "en_US", status: "pending", meta_template_id: nil) }

    it "atualiza o status pelo nome e idioma (com hífen no webhook), com o motivo da rejeição" do
      event = ->(name, extra = {}) { process_change("message_template_status_update", { event: name, message_template_id: 1_689_556_908_129_832,
                                                                                         message_template_name: "order_confirmation", message_template_language: "en-US",
                                                                                         reason: "NONE", message_template_category: "UTILITY" }.merge(extra), entry_id: account.waba_id) }
      event.call("APPROVED")
      expect(template.reload).to have_attributes(status: "approved", rejection_reason: nil, last_synced_at: Time.current)

      event.call("FLAGGED")
      expect(template.reload.status).to eq("approved")

      event.call("REJECTED", reason: "INVALID_FORMAT", rejection_info: { reason: "Parâmetros colados." })
      expect(template.reload).to have_attributes(status: "rejected", rejection_reason: "INVALID_FORMAT — Parâmetros colados.")

      event.call("REINSTATED")
      expect(template.reload.status).to eq("approved")
    end

    it "troca a categoria só quando a mudança foi concluída" do
      base = { message_template_id: 1, message_template_name: "order_confirmation", message_template_language: "en_US" }
      process_change("template_category_update", base.merge(new_category: "UTILITY", correct_category: "MARKETING"), entry_id: account.waba_id)
      expect(template.reload.category).to eq("utility")
      process_change("template_category_update", base.merge(previous_category: "UTILITY", new_category: "MARKETING"), entry_id: account.waba_id)
      expect(template.reload.category).to eq("marketing")
    end
  end

  it "ignora campo que o Admin não trata" do
    expect { process_change("business_capability_update", { max_daily_conversation_per_phone: 1000 }, entry_id: account.waba_id) }.not_to raise_error
  end
end
