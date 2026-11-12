require "rails_helper"

RSpec.describe "Próximos passos" do
  # Quarta-feira, 11/11/2026, 10:00 em Brasília.
  let(:now) { Time.zone.local(2026, 11, 11, 10) }
  let(:admin) { create(:user) }

  around { |example| travel_to(now) { example.run } }

  describe NextStepSchedulable do
    it "guarda data e hora em Brasília e põe 09:00 quando vem só a data" do
      lead = create(:lead, next_step_on: "2026-11-12T14:30")
      expect(lead.reload.next_step_on).to eq(Time.zone.local(2026, 11, 12, 14, 30))
      expect(lead.next_step_on.utc_offset).to eq(-3 * 3600)

      lead.update!(next_step_on: "2026-11-20")
      expect(lead.reload.next_step_on).to eq(Time.zone.local(2026, 11, 20, 9))
      lead.update!(next_step_on: Date.new(2026, 11, 21))
      expect(lead.reload.next_step_on).to eq(Time.zone.local(2026, 11, 21, 9))
    end

    it "entende o horário com fuso e recusa texto que não é data" do
      expect(described_class.cast("2026-11-12T14:30:00Z")).to eq(Time.zone.local(2026, 11, 12, 11, 30))
      expect(described_class.cast("amanhã")).to be_nil
      expect(described_class.cast("2026-13-45")).to be_nil
      expect(described_class.cast("")).to be_nil
    end

    it "calcula os atalhos do Adiar" do
      expect(described_class.postpone_time("1h")).to eq(Time.zone.local(2026, 11, 11, 11))
      expect(described_class.postpone_time("amanha")).to eq(Time.zone.local(2026, 11, 12, 9))
      expect(described_class.postpone_time("segunda")).to eq(Time.zone.local(2026, 11, 16, 9))
      expect(described_class.postpone_time("outra")).to be_nil
    end
  end

  describe NextStepList do
    def list(**options)
      described_class.new(leads: Lead.all, opportunities: Opportunity.all, **options)
    end

    let!(:late_opportunity) { create(:opportunity, title: "Portal", next_step: "Cobrar retorno", next_step_on: now - 2.days) }
    let!(:late_today) { create(:lead, name: "Ana", next_step: "Ligar", next_step_on: now - 1.hour) }
    let!(:today) { create(:lead, name: "Bia", next_step: "Mandar proposta", next_step_on: now + 3.hours) }
    let!(:tomorrow) { create(:opportunity, title: "App", next_step: "Reunião", next_step_on: now + 1.day) }
    let!(:week) { create(:lead, name: "Caio", next_step: "Follow-up", next_step_on: now + 5.days) }
    let!(:later) { create(:lead, name: "Duda", next_step: "Reativar", next_step_on: now + 30.days) }
    let!(:undated) { create(:lead, name: "Eva", next_step: nil, next_step_on: nil) }

    before do
      create(:lead, name: "Convertido", status: "converted", next_step_on: now - 3.days)
      create(:lead, name: "Perdido", status: "lost", lost_reason: "Preço", next_step_on: now - 3.days)
      create(:opportunity, title: "Ganha", stage: "won", next_step_on: now - 3.days)
    end

    it "junta leads e oportunidades em aberto, do mais antigo para o mais novo, com os sem data no fim" do
      expect(list.items.map(&:record)).to eq([ late_opportunity, late_today, today, tomorrow, week, later, undated ])
    end

    it "agrupa em atrasados, hoje, amanhã, próximos 7 dias, depois e sem próximo passo" do
      groups = list.groups.transform_values { |items| items.map(&:record) }
      expect(groups).to eq(
        "atrasados" => [ late_opportunity, late_today ], "hoje" => [ today ], "amanha" => [ tomorrow ],
        "proximos_7_dias" => [ week ], "depois" => [ later ], "sem_data" => [ undated ]
      )
    end

    it "filtra por tipo, responsável e origem (na oportunidade, a do lead de onde veio)" do
      expect(list(kind: "oportunidade").items.map(&:record)).to eq([ late_opportunity, tomorrow ])

      today.update!(user: admin)
      expect(list(user_id: admin.id).items.map(&:record)).to eq([ today ])

      week.update!(origin: "referral")
      tomorrow.update!(lead: create(:lead, origin: "referral", status: "converted"))
      expect(list(origin: "referral").items.map(&:record)).to eq([ tomorrow, week ])
    end

    it "limita pelo período, com os atrasados e os sem data só quando pedidos" do
      period = { from: now.beginning_of_day + 1.day, to: (now + 7.days).end_of_day }
      expect(list(**period, include_undated: false).items.map(&:record)).to eq([ late_opportunity, late_today, tomorrow, week ])
      expect(list(**period, include_overdue: false, include_undated: false).items.map(&:record)).to eq([ tomorrow, week ])
      expect(list(include_overdue: false, include_undated: true, from: now).items.map(&:record)).to eq([ today, tomorrow, week, later, undated ])
    end

    it "traz o WhatsApp da oportunidade pelo lead ou pelo contato principal da empresa" do
      create(:contact, company: late_opportunity.company, primary: true, whatsapp: "11 98888-7777")
      expect(list.items.find { |item| item.record == late_opportunity }.whatsapp).to eq("11 98888-7777")

      late_opportunity.update!(lead: create(:lead, whatsapp: "11 97777-6666", status: "converted"))
      expect(list.items.find { |item| item.record == late_opportunity }.whatsapp).to eq("11 97777-6666")
    end

    it "acha a última interação de cada registro numa consulta" do
      create(:interaction, subject: today, notes: "Antiga", occurred_on: now.to_date - 5)
      newest = create(:interaction, subject: today, notes: "Recente", occurred_on: now.to_date)
      on_opportunity = create(:interaction, subject: tomorrow, notes: "Na oportunidade")
      last = described_class.last_interactions([ today, tomorrow, undated ])
      expect(last).to eq([ "Lead", today.id ] => newest, [ "Opportunity", tomorrow.id ] => on_opportunity)
    end
  end

  describe NextStepCompletion do
    let(:lead) { create(:lead, next_step: "Ligar", next_step_on: now - 1.hour) }

    def complete(**attributes)
      described_class.new(record: lead, user: admin, notes: "Liguei, pediu proposta", kind: "call", **attributes)
    end

    it "grava a interação e o novo próximo passo" do
      completion = complete(outcome: "next_step", next_step: "Enviar proposta", next_step_on: "2026-11-13T15:00")
      expect(completion.save).to be(true)
      expect(lead.reload).to have_attributes(next_step: "Enviar proposta", next_step_on: Time.zone.local(2026, 11, 13, 15), status: "new")
      expect(lead.interactions.sole).to have_attributes(kind: "call", notes: "Liguei, pediu proposta", occurred_on: now.to_date, user: admin)
    end

    it "grava a interação e marca como perdido com o motivo" do
      expect(complete(outcome: "lost", lost_reason: "Preço", lost_details: "Achou caro").save).to be(true)
      expect(lead.reload).to have_attributes(status: "lost", lost_reason: "Preço", lost_details: "Achou caro")
      expect(lead.interactions.count).to eq(1)
    end

    it "não deixa sair sem próximo passo nem perdido, e não grava nada" do
      [ complete(outcome: nil), complete(outcome: "next_step", next_step: "Enviar proposta"),
        complete(outcome: "next_step", next_step_on: "2026-11-13T15:00"), complete(outcome: "lost") ].each do |completion|
        expect(completion.save).to be(false)
      end
      expect(complete(outcome: nil).tap(&:validate).errors.full_messages).to include(start_with("Defina o próximo passo"))
      expect(lead.reload).to have_attributes(next_step: "Ligar", status: "new")
      expect(Interaction.count).to eq(0)
    end

    it "exige o que foi feito, um tipo de interação válido e um motivo da lista" do
      expect(complete(notes: "", outcome: "lost", lost_reason: "Preço").save).to be(false)
      expect(complete(kind: "sinal", outcome: "lost", lost_reason: "Preço").save).to be(false)
      completion = complete(outcome: "lost", lost_reason: "Inventado")
      expect(completion.save).to be(false)
      expect(completion.errors.full_messages).to include("Motivo da perda não está na lista de motivos")
    end

    it "recusa registro que não está em aberto" do
      lead.update!(status: "converted")
      expect(complete(outcome: "next_step", next_step: "X", next_step_on: "2026-11-13").save).to be(false)
    end
  end

  describe "migração para data e hora" do
    require Rails.root.join("db/migrate/20261111150000_change_next_step_on_to_datetime")

    let(:migration) { ChangeNextStepOnToDatetime.new }

    after do
      [ Lead, Opportunity ].each(&:reset_column_information)
    end

    it "leva as datas para o mesmo dia às 09:00 de Brasília e volta sem perder o dia" do
      lead = create(:lead)
      opportunity = create(:opportunity)
      undated = create(:lead)
      ActiveRecord::Migration.suppress_messages do
        migration.migrate(:down)
        Lead.connection.execute("UPDATE leads SET next_step_on = '2026-11-05' WHERE id = '#{lead.id}'")
        Lead.connection.execute("UPDATE opportunities SET next_step_on = '2026-12-01' WHERE id = '#{opportunity.id}'")
        migration.migrate(:up)
      end
      [ Lead, Opportunity ].each(&:reset_column_information)

      expect(lead.reload.next_step_on).to eq(Time.zone.local(2026, 11, 5, 9))
      expect(Lead.connection.select_value("SELECT next_step_on FROM leads WHERE id = '#{lead.id}'").to_s).to start_with("2026-11-05 12:00:00")
      expect(opportunity.reload.next_step_on).to eq(Time.zone.local(2026, 12, 1, 9))
      expect(undated.reload.next_step_on).to be_nil

      ActiveRecord::Migration.suppress_messages { migration.migrate(:down) }
      expect(Lead.connection.select_value("SELECT next_step_on FROM leads WHERE id = '#{lead.id}'").to_s).to eq("2026-11-05")
      ActiveRecord::Migration.suppress_messages { migration.migrate(:up) }
    end
  end
end
