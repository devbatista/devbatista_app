require "rails_helper"
require "turbo/broadcastable/test_helper"

RSpec.describe "Escritório de agentes de IA" do
  include Turbo::Broadcastable::TestHelper

  let(:admin) { create(:user, :admin) }
  let(:agent) { create(:agent, key: "sol", name: "Sol") }

  describe Agent do
    it "cria os 5 agentes iniciais na ordem das salas, sem duplicar" do
      2.times { described_class.seed_defaults! }
      expect(described_class.ordered.pluck(:key, :name, :title, :room)).to eq([
        %w[ops Ops SRE Infra], %w[sol Sol SDR Comercial], %w[mia Mia Marketing Marketing],
        [ "leo", "Leo", "Tráfego pago", "Tráfego pago" ], %w[fin Fin Financeiro Financeiro]
      ])
    end

    it "valida a chave e as cores do sprite" do
      expect(build(:agent, key: "Sol 2", outfit_color: "azul")).to be_invalid
      expect(build(:agent, key: "sol_2", outfit_color: "#ABCDEF")).to be_valid
      create(:agent, key: "ops")
      expect(build(:agent, key: "ops")).to be_invalid
    end

    it "usa a chave na URL" do
      expect(agent.to_param).to eq("sol")
    end

    describe "#status" do
      it "é o do último evento; sem evento, Ocioso" do
        expect(agent.status).to eq("idle")
        create(:agent_event, agent: agent, status: "working", created_at: 2.minutes.ago)
        create(:agent_event, agent: agent, status: "error", created_at: 1.minute.ago)
        expect(agent.reload.status).to eq("error")
        expect(agent.status_label).to eq("Erro")
      end

      it "volta a Ocioso quando o pedido de aprovação já foi decidido" do
        event = create(:agent_event, :approval, agent: agent)
        expect(agent.reload.status).to eq("awaiting_approval")
        event.decide!("approved", by: admin)
        expect(agent.reload.status).to eq("idle")
      end
    end

    it "carrega o último evento de vários agentes numa consulta" do
      other = create(:agent)
      create(:agent_event, agent: agent, title: "Antigo", created_at: 1.hour.ago)
      latest = create(:agent_event, agent: agent, title: "Novo")
      agents = described_class.preload_latest_events(described_class.where(id: [ agent.id, other.id ]).to_a)
      expect(agents.find { |a| a.id == agent.id }.latest_event).to eq(latest)
      expect(agents.find { |a| a.id == other.id }.latest_event).to be_nil
    end

    it "lista no painel as ordens pendentes e as concluídas hoje" do
      pending = create(:agent_order, agent: agent)
      today = create(:agent_order, agent: agent, status: "completed", response: "Feito", completed_at: 1.hour.ago)
      create(:agent_order, agent: agent, status: "completed", response: "Feito", completed_at: 2.days.ago)
      expect(agent.panel_orders).to contain_exactly(pending, today)
    end
  end

  describe AgentEvent do
    it "pedir aprovação e aguardar aprovação andam juntos, com a decisão pendente" do
      by_flag = create(:agent_event, agent: agent, status: "done", needs_approval: true)
      by_status = create(:agent_event, agent: agent, status: "awaiting_approval")
      [ by_flag, by_status ].each { |event| expect(event).to have_attributes(status: "awaiting_approval", needs_approval: true, decision: "pending") }
      expect(create(:agent_event, agent: agent)).to have_attributes(needs_approval: false, decision: nil)
    end

    it "o banco recusa aprovação sem o status ou sem decisão" do
      event = create(:agent_event, agent: agent)
      expect { event.update_columns(needs_approval: true) }.to raise_error(ActiveRecord::StatementInvalid, /agent_events_approval/)
    end

    it "decide uma vez só, com quem e quando" do
      event = create(:agent_event, :approval, agent: agent)
      event.decide!("rejected", by: admin, note: "Espere a proposta nova.")
      expect(event.reload).to have_attributes(decision: "rejected", decided_by: admin, decision_note: "Espere a proposta nova.")
      expect(event.decided_at).to be_present
      expect { event.decide!("approved", by: admin) }.to raise_error(ActiveRecord::RecordInvalid, /já foi registrada/)
      expect(event.reload.decision).to eq("rejected")
    end

    it "recusa decisão inválida e decisão de evento sem aprovação" do
      expect { create(:agent_event, :approval, agent: agent).decide!("pending", by: admin) }.to raise_error(ActiveRecord::RecordInvalid, /inválida/)
      expect { create(:agent_event, agent: agent).decide!("approved", by: admin) }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "limita o título e os dados" do
      expect(build(:agent_event, agent: agent, title: "x" * 121)).to be_invalid
      expect(build(:agent_event, agent: agent, payload: { texto: "x" * 21.kilobytes })).to be_invalid
      expect(build(:agent_event, agent: agent, payload: { leads: 3 })).to be_valid
    end

    it "audita a criação e a decisão na área agentes, sem histórico de negócio" do
      Current.set(user: admin) do
        event = create(:agent_event, :approval, agent: agent)
        event.decide!("approved", by: admin)
        expect(AuditLog.where(auditable: event).pluck(:action, :area)).to contain_exactly(%w[create agentes], %w[update agentes])
      end
      expect(Activity.where(area: "agentes")).to be_empty
    end

    it "novo evento e decisão redesenham a sala e o painel do agente no stream escritorio" do
      event = nil
      streams = capture_turbo_stream_broadcasts(:escritorio) do
        perform_enqueued_jobs(only: Turbo::Streams::ActionBroadcastJob) { event = create(:agent_event, :approval, agent: agent, title: "Enviar follow-up") }
      end
      targets = streams.map { |s| s["target"] }
      expect(targets).to eq([ ActionView::RecordIdentifier.dom_id(agent, :desk), ActionView::RecordIdentifier.dom_id(agent, :panel),
                              ActionView::RecordIdentifier.dom_id(agent, :log) ])
      expect(streams.first.to_html).to include("Enviar follow-up", "Aguardando aprovação", %(data-agent-status="awaiting_approval"))
      expect(streams.second.to_html).to include(%(src="/office/agents/sol/live"))
      expect(streams.third.to_html).to include(%(src="/office/agents/sol/log"))

      decided = capture_turbo_stream_broadcasts(:escritorio) do
        perform_enqueued_jobs(only: Turbo::Streams::ActionBroadcastJob) { event.decide!("approved", by: admin) }
      end
      expect(decided.first.to_html).to include("Ocioso")
    end
  end

  describe AgentOrder do
    it "conclui uma vez só, com a resposta" do
      order = create(:agent_order, agent: agent)
      order.complete!("Feito: 3 leads priorizados.")
      expect(order.reload).to have_attributes(status: "completed", response: "Feito: 3 leads priorizados.")
      expect(order.completed_at).to be_present
      expect { order.complete!("De novo") }.to raise_error(ActiveRecord::RecordInvalid, /já está concluída/)
    end

    it "exige o texto e a resposta ao concluir" do
      expect(build(:agent_order, agent: agent, body: "")).to be_invalid
      expect { create(:agent_order, agent: agent).complete!("") }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end
end
