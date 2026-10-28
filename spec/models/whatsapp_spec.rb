require "rails_helper"

RSpec.describe "WhatsApp" do
  describe WhatsappAccount do
    it "guarda o token criptografado e lê de volta" do
      account = create(:whatsapp_account, access_token: "EAAG-token-muito-secreto")
      raw = described_class.connection.select_value(
        described_class.where(id: account.id).select(:access_token).to_sql
      )
      expect(raw).not_to include("token-muito-secreto")
      expect(account.reload.access_token).to eq("EAAG-token-muito-secreto")
    end

    it "audita a conexão sem levar o token para a trilha" do
      account = create(:whatsapp_account, status: "pending")
      account.update!(status: "connected", access_token: "token-novo")
      logs = AuditLog.where(auditable: account)
      expect(logs.pluck(:area).uniq).to eq([ "whatsapp" ])
      expect(logs.map(&:action)).to eq(%w[create status_change])
      expect(logs.flat_map { |log| log.changeset.keys }).not_to include("access_token")
    end

    it "não repete o mesmo número e mostra o limite de envio da Meta" do
      account = create(:whatsapp_account, messaging_limit_tier: "TIER_2K")
      expect(build(:whatsapp_account, phone_number_id: account.phone_number_id)).not_to be_valid
      expect(account.messaging_limit_label).to eq("2.000")
      expect(account.quality_rating_label).to eq("Desconhecida")
      expect(account.to_s).to eq("DevBatista · +55 11 97070-2026")
    end
  end

  describe WhatsappConversation do
    it "aceita conversa só com o BSUID, sem telefone nem @usuário" do
      conversation = build(:whatsapp_conversation, wa_id: nil, username: nil, profile_name: nil, bsuid: "BR.11803477661209384712")
      expect(conversation).to be_valid
      expect(conversation.display_name).to eq("Contato do WhatsApp")
      expect(conversation.recipient_params).to eq(recipient: "BR.11803477661209384712")
    end

    it "mostra o nome da agenda, depois o do perfil, o telefone e o @usuário" do
      conversation = build(:whatsapp_conversation, saved_name: "Henrique (agenda)", profile_name: "Henrique", wa_id: "5511991023344", username: "henrique.d")
      expect(conversation.display_name).to eq("Henrique (agenda)")
      conversation.saved_name = nil
      expect(conversation.display_name).to eq("Henrique")
      conversation.profile_name = nil
      expect(conversation.display_name).to eq("+55 11 99102-3344")
      conversation.wa_id = nil
      expect(conversation.display_name).to eq("@henrique.d")
      expect(build(:whatsapp_conversation, wa_id: "14155550123").phone_label).to eq("+14155550123")
    end

    it "prefere o telefone como destinatário e guarda só os dígitos" do
      conversation = build(:whatsapp_conversation, wa_id: "+55 (11) 99102-3344")
      expect(conversation.wa_id).to eq("5511991023344")
      expect(conversation.recipient_params).to eq(to: "5511991023344")
    end

    it "exige BSUID ou telefone, no model e no banco" do
      conversation = build(:whatsapp_conversation, account: create(:whatsapp_account), bsuid: nil, wa_id: nil)
      expect(conversation).not_to be_valid
      expect { conversation.save!(validate: false) }.to raise_error(ActiveRecord::StatementInvalid, /whatsapp_conversations_identified/)
    end

    it "liga a um lead ou a um contato, não aos dois" do
      conversation = build(:whatsapp_conversation, account: create(:whatsapp_account), lead: create(:lead), contact: create(:contact))
      expect(conversation).not_to be_valid
      expect { conversation.save!(validate: false) }.to raise_error(ActiveRecord::StatementInvalid, /whatsapp_conversations_single_link/)
    end

    it "o BSUID é único por conta, e outra conta pode ter o mesmo" do
      existing = create(:whatsapp_conversation)
      same_account = build(:whatsapp_conversation, account: existing.account, bsuid: existing.bsuid)
      expect(same_account).not_to be_valid
      expect { same_account.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
      expect(build(:whatsapp_conversation, bsuid: existing.bsuid)).to be_valid
    end

    it "abre a janela de 24h pela última mensagem recebida" do
      freeze_time do
        conversation = create(:whatsapp_conversation, last_inbound_at: 23.hours.ago)
        closed = create(:whatsapp_conversation, last_inbound_at: 25.hours.ago)
        never = create(:whatsapp_conversation, last_inbound_at: nil)
        expect(conversation.window_open?).to be(true)
        expect(conversation.window_closes_at).to eq(1.hour.from_now)
        expect([ closed, never ].map(&:window_open?)).to eq([ false, false ])
        expect(described_class.window_open).to contain_exactly(conversation)
      end
    end

    it "fica sem vínculo quando o lead é excluído" do
      lead = create(:lead)
      conversation = create(:whatsapp_conversation, lead: lead, unread_count: 2)
      expect(described_class.unlinked).not_to include(conversation)
      expect(described_class.unread).to include(conversation)
      lead.destroy!
      expect(conversation.reload.lead_id).to be_nil
      expect(described_class.unlinked).to include(conversation)
    end
  end

  describe WhatsappMessage do
    it "não grava o mesmo wa_message_id duas vezes" do
      message = create(:whatsapp_message)
      duplicate = build(:whatsapp_message, conversation: message.conversation, wa_message_id: message.wa_message_id)
      expect(duplicate).not_to be_valid
      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "permite várias mensagens ainda sem wa_message_id (antes da resposta da Meta)" do
      conversation = create(:whatsapp_conversation)
      create_list(:whatsapp_message, 2, :outbound, conversation: conversation, wa_message_id: nil, status: "pending")
      expect(conversation.messages.count).to eq(2)
    end

    it "confere origem e status com a direção" do
      expect(build(:whatsapp_message, origin: "admin")).not_to be_valid
      expect(build(:whatsapp_message, :outbound, status: "received")).not_to be_valid
      expect(build(:whatsapp_message, :outbound, origin: "phone", user: nil)).to be_valid
    end

    it "liga a resposta à mensagem citada" do
      quoted = create(:whatsapp_message, :outbound, body: "Confirmando: terça, 22/09 às 10h.")
      reply = create(:whatsapp_message, conversation: quoted.conversation, reply_to_wa_message_id: quoted.wa_message_id, body: "Combinado!")
      expect(reply.reply_to).to eq(quoted)
    end

    it "guarda a reação sobre a mensagem reagida, fora da linha do tempo" do
      reaction = create(:whatsapp_message, :reaction, reaction_emoji: "❤️")
      target = reaction.conversation.messages.find_by!(wa_message_id: reaction.reaction_to_wa_message_id)
      expect(target.reactions).to contain_exactly(reaction)
      expect(reaction.conversation.messages.timeline).to contain_exactly(target)
      removal = create(:whatsapp_message, :reaction, conversation: target.conversation, reaction_to_wa_message_id: target.wa_message_id, reaction_emoji: "",
                                                          sent_at: 1.minute.from_now)
      expect(target.reactions.reload.last).to eq(removal)
      expect(build(:whatsapp_message, kind: "reaction", reaction_to_wa_message_id: nil)).not_to be_valid
    end

    it "exige nome e idioma no template e guarda a mídia no Active Storage" do
      expect(build(:whatsapp_message, :outbound, kind: "template")).not_to be_valid
      message = create(:whatsapp_message, :outbound, kind: "template", template_name: "lembrete_proposta", template_language: "pt_BR",
                                                     template_params: [ "Beatriz", "Novo site", "20/09/2026" ])
      expect(message.reload.template_params).to eq([ "Beatriz", "Novo site", "20/09/2026" ])
      image = create(:whatsapp_message, kind: "image", body: nil, media_id: "1234567890", media_mime_type: "image/jpeg")
      image.media.attach(io: StringIO.new("jpeg"), filename: "foto.jpg", content_type: "image/jpeg")
      expect(image.media).to be_attached
    end
  end

  describe WhatsappTemplate do
    it "conta as variáveis do cabeçalho e do corpo, numeradas ou com nome" do
      template = create(:whatsapp_template, components: [
        { "type" => "HEADER", "format" => "TEXT", "text" => "Proposta {{1}}" },
        { "type" => "BODY", "text" => "Olá, {{1}}. A proposta {{2}} vence em {{3}}. Até {{3}}!" },
        { "type" => "FOOTER", "text" => "DevBatista" }
      ])
      expect(template.variables_count).to eq(4)
      expect(template.body_text).to start_with("Olá, {{1}}")
      template.update!(components: [ { "type" => "BODY", "text" => "Oi, {{nome}}! Sobre {{assunto}}." } ])
      expect(template.variables_count).to eq(2)
    end

    it "valida o nome no formato da Meta e não repete nome e idioma na conta" do
      template = create(:whatsapp_template, name: "lembrete_reuniao")
      expect(build(:whatsapp_template, name: "Lembrete Reunião")).not_to be_valid
      expect(build(:whatsapp_template, account: template.account, name: "lembrete_reuniao")).not_to be_valid
      expect(build(:whatsapp_template, account: template.account, name: "lembrete_reuniao", language: "en_US")).to be_valid
    end

    it "só os aprovados ficam disponíveis para envio" do
      approved = create(:whatsapp_template, status: "approved")
      create(:whatsapp_template, account: approved.account, status: "rejected", rejection_reason: "INCORRECT_CATEGORY")
      expect(described_class.usable).to contain_exactly(approved)
    end
  end
end
