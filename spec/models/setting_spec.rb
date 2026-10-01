require "rails_helper"

RSpec.describe Setting do
  it "usa o valor padrão enquanto ninguém alterou" do
    expect(described_class[:contract_alert_days]).to eq([ 60, 30, 15 ])
  end

  it "guarda e devolve o valor alterado, com auditoria" do
    described_class[:contract_alert_days] = [ 90, 30 ]
    expect(described_class[:contract_alert_days]).to eq([ 90, 30 ])
    expect(AuditLog.where(auditable_type: "Setting").count).to eq(1)
  end

  it "recusa chave desconhecida" do
    expect { described_class[:qualquer] = 1 }.to raise_error(ActiveRecord::RecordInvalid)
  end
end
