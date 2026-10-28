require "rails_helper"
require "rake"
require "turbo/broadcastable/test_helper"

RSpec.describe "Vínculo da conversa com o CRM" do
  include Turbo::Broadcastable::TestHelper

  let(:account) { create(:whatsapp_account, status: "connected") }

  def webhook_conversation
    process_webhook(account, "messages", contacts: [ wa_contact ], messages: [ wa_message("wamid.V1", "Oi, tudo bem?") ])
    account.conversations.sole
  end

  describe "vínculo automático pelo telefone" do
    it "liga a conversa nova ao único lead em aberto, com o número gravado sem o nono dígito" do
      lead = create(:lead, whatsapp: "(11) 9102-3344")

      conversation = webhook_conversation

      expect(conversation).to have_attributes(lead: lead, contact: nil, linked_by: nil)
      expect(conversation.linked_at).to be_present
    end

    it "acha o contato pelo telefone do cadastro, com o 55" do
      contact = create(:contact, phone: "+55 11 99102-3344")
      expect(webhook_conversation.contact).to eq(contact)
    end

    it "não vincula com mais de um candidato nem só com lead encerrado, mas os mostra como candidatos" do
      lead = create(:lead, whatsapp: "11991023344")
      contact = create(:contact, whatsapp: "(11) 99102-3344")
      lost = create(:lead, whatsapp: "11 99102-3344", status: "lost", lost_reason: "Sem orçamento")

      conversation = webhook_conversation

      expect(conversation).not_to be_linked
      expect(conversation.matching_leads).to contain_exactly(lead, lost)
      expect(conversation.matching_contacts).to contain_exactly(contact)

      lead.update!(status: "lost", lost_reason: "Sem orçamento")
      contact.destroy!
      expect(conversation.reload.auto_link!).to be(false) # só leads perdidos
    end

    it "liga as conversas sem vínculo quando o lead ganha o WhatsApp depois, sem mexer nas já ligadas" do
      conversation = webhook_conversation
      linked = create(:whatsapp_conversation, account: account, wa_id: "551191023344", bsuid: nil, lead: create(:lead))
      lead = create(:lead, whatsapp: nil)

      expect { lead.update!(whatsapp: "(11) 99102-3344") }.to have_enqueued_job(WhatsappAutoLinkJob).with(lead)
      perform_enqueued_jobs(only: WhatsappAutoLinkJob)

      expect(conversation.reload.lead).to eq(lead)
      expect(linked.reload.lead).not_to eq(lead)
    end

    describe "conversa desvinculada à mão" do
      let!(:lead) { create(:lead, whatsapp: "(11) 99102-3344") }
      let(:conversation) { webhook_conversation.tap(&:unlink!) }

      def link_conversations
        Rails.application.load_tasks unless Rake::Task.task_defined?("whatsapp:link_conversations")
        expect { Rake::Task["whatsapp:link_conversations"].execute }.to output("0 conversa(s) vinculada(s) pelo telefone.\n").to_stdout
      end

      it "fica marcada e não volta a se ligar sozinha: nem por mensagem nova, nem pelo cadastro salvo de novo, nem pela rake" do
        expect(conversation).to have_attributes(lead: nil, auto_link_blocked_at: be_present)
        expect(WhatsappConversation.auto_linkable).not_to include(conversation)

        process_webhook(account, "messages", contacts: [ wa_contact ], messages: [ wa_message("wamid.V2", "Alô?", at: Time.zone.parse("2026-10-27 10:30")) ])
        lead.update!(whatsapp: "11 99102-3344")
        perform_enqueued_jobs(only: WhatsappAutoLinkJob)
        link_conversations

        expect(conversation.reload).not_to be_linked
        expect(conversation.auto_link!).to be(false)
      end

      it "volta a poder se ligar sozinha quando ganha outro telefone" do
        other_lead = create(:lead, whatsapp: "(21) 98888-1234")
        conversation.update!(wa_id: "5521988881234")
        expect(conversation.reload).to have_attributes(lead: other_lead, auto_link_blocked_at: nil, linked_by: nil)
      end

      it "vincular à mão tira a marca" do
        conversation.link!(lead, user: lead.user)
        expect(conversation.reload).to have_attributes(lead: lead, auto_link_blocked_at: nil)
      end
    end

    it "a conversa juntada pela troca de BSUID leva o vínculo e a interação do dia" do
      lead = create(:lead)
      by_phone = create(:whatsapp_conversation, account: account, wa_id: WhatsappWebhookHelpers::CONTACT_PHONE, bsuid: nil, last_message_at: 1.hour.ago)
      by_phone.link!(lead, user: lead.user)
      interaction = create(:interaction, subject: lead, kind: "whatsapp", whatsapp_conversation: by_phone, occurred_on: Date.current)
      by_bsuid = create(:whatsapp_conversation, account: account, wa_id: nil, bsuid: WhatsappWebhookHelpers::CONTACT_BSUID)

      WhatsappConversation.locate!(account, bsuid: WhatsappWebhookHelpers::CONTACT_BSUID, wa_id: WhatsappWebhookHelpers::CONTACT_PHONE)

      expect(by_bsuid.reload).to have_attributes(lead: lead, linked_by: lead.user)
      expect(interaction.reload.whatsapp_conversation).to eq(by_bsuid)
    end

    it "troca o painel aberto por um turbo-frame que busca o painel com a sessão de quem vê" do
      conversation = create(:whatsapp_conversation, account: account)
      lead = create(:lead, name: "Henrique Duarte", email: "henrique@gruponorte.com.br")

      streams = capture_turbo_stream_broadcasts([ conversation, :whatsapp ]) do
        perform_enqueued_jobs(only: Turbo::Streams::ActionBroadcastJob) { conversation.link!(lead, user: lead.user) }
      end

      panel = streams.find { |stream| stream["target"] == ActionView::RecordIdentifier.dom_id(conversation, :panel) }
      expect(panel["action"]).to eq("replace")
      expect(panel.to_html).to include(%(src="/whatsapp/conversations/#{conversation.id}/panel")).and(exclude("henrique@gruponorte"))
    end
  end

  describe WhatsappInteractionJob do
    let(:owner) { create(:user, name: "Rafael Batista") }
    let(:lead) { create(:lead, user: owner) }
    let(:conversation) { create(:whatsapp_conversation, account: account, lead: lead, last_message_at: 2.hours.ago) }

    def record(*traits, **attributes)
      message = create(:whatsapp_message, *traits, conversation: conversation, sent_at: Time.current, **attributes)
      conversation.record_message!(message)
      message
    end

    it "registra uma interação por dia no lead, em nome do responsável, só com as contagens" do
      conversation
      clear_enqueued_jobs
      record(body: "Meu orçamento é até 8 mil")
      record(body: "Consegue terça?")
      record(:outbound, body: "Consigo sim")
      record(:outbound, body: "Falhou", status: "failed")
      record(body: "antiga", from_history: true)
      record(kind: "reaction", reaction_emoji: "👍", reaction_to_wa_message_id: "wamid.X")

      expect(WhatsappInteractionJob).to have_been_enqueued.exactly(3).times
      perform_enqueued_jobs(only: described_class)

      interaction = lead.interactions.sole
      expect(interaction).to have_attributes(kind: "whatsapp", user: owner, occurred_on: Date.current, whatsapp_conversation: conversation,
                                             notes: "Conversa do dia · 2 recebidas, 1 enviada")
      expect(interaction).to be_automatic

      record(:outbound, body: "Até terça")
      perform_enqueued_jobs(only: described_class)
      expect(lead.interactions.sole.notes).to eq("Conversa do dia · 2 recebidas, 2 enviadas")
      expect(lead.interactions.sole.notes).not_to include("orçamento")
    end

    it "no contato, vai para a oportunidade aberta da empresa; sem ela, não registra" do
      contact = create(:contact)
      opportunity = create(:opportunity, company: contact.company)
      conversation.update!(lead: nil, contact: contact)
      record(body: "Segue o comprovante")
      perform_enqueued_jobs(only: described_class)
      expect(opportunity.interactions.sole).to have_attributes(user: opportunity.user, notes: "Conversa do dia · 1 recebida")

      opportunity.update!(stage: "won")
      clear_enqueued_jobs
      expect { described_class.perform_now(conversation, Date.current.iso8601) }.not_to change(Interaction, :count)
    end

    it "no lead convertido, vai para a oportunidade aberta que ele virou" do
      opportunity = create(:opportunity, lead: lead)
      lead.update!(status: "converted")
      record(body: "Oi")
      perform_enqueued_jobs(only: described_class)
      expect(opportunity.interactions.sole.kind).to eq("whatsapp")
      expect(lead.interactions).to be_empty
    end

    it "vincular registra a interação de hoje; conversa sem vínculo não registra nada" do
      unlinked = create(:whatsapp_conversation, account: account, last_message_at: 1.hour.ago)
      message = create(:whatsapp_message, conversation: unlinked, sent_at: 10.minutes.ago)
      expect { unlinked.record_message!(message) }.not_to have_enqueued_job(described_class)

      expect { unlinked.link!(lead, user: owner) }.to have_enqueued_job(described_class).with(unlinked, Date.current.iso8601)
      perform_enqueued_jobs(only: described_class)
      expect(lead.interactions.sole.notes).to eq("Conversa do dia · 1 recebida")
    end
  end
end
