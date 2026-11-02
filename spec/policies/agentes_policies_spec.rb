require "rails_helper"

RSpec.describe "Permissões do escritório de agentes" do
  let(:admin) { create(:user, :admin) }
  let(:comercial) { create(:user, :comercial) }
  let(:records) do
    agent = create(:agent)
    [ agent, create(:agent_event, :approval, agent: agent), create(:agent_order, agent: agent) ]
  end

  def policy(user, record)
    Pundit.policy!(user, record)
  end

  it "na v1, só o administrador tem a área" do
    expect(Role::AREAS).to include("agentes" => "Agentes IA")
    expect(Role::DEFAULTS.except("admin").values.map { |attrs| attrs[:permissions]["agentes"] }.uniq).to eq([ nil ])
    expect(admin.role.level_for("agentes")).to eq("full")
    expect(comercial.role.level_for("agentes")).to eq("none")
  end

  it "o administrador vê, decide e deixa ordens" do
    records.each { |record| expect(policy(admin, record)).to have_attributes(index?: true, show?: true, create?: true, update?: true) }
    expect(policy(admin, records.second).decide?).to be(true)
  end

  it "os outros perfis não veem nada enquanto a área não for liberada" do
    records.each { |record| expect(policy(comercial, record)).to have_attributes(index?: false, create?: false, update?: false) }
    expect(policy(comercial, records.second).decide?).to be(false)
    expect(Pundit.policy_scope!(comercial, AgentEvent)).to be_empty
    expect(Pundit.policy_scope!(admin, AgentEvent)).to contain_exactly(records.second)
  end

  it "liberada só para leitura, o perfil acompanha mas não decide nem deixa ordem" do
    comercial.role.update!(permissions: comercial.role.permissions.merge("agentes" => "read"))
    _agent, event, order = records
    expect(policy(comercial, event)).to have_attributes(show?: true, decide?: false)
    expect(policy(comercial, order)).to have_attributes(show?: true, create?: false)
  end
end
