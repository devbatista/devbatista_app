require "rails_helper"

RSpec.describe AuditLog do
  let(:log) { described_class.record!(action: "login", area: "acesso", label: "teste") }

  it "não pode ser alterado pelo model" do
    expect { log.update!(area: "outra") }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it "não pode ser excluído pelo model" do
    expect { log.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it "é protegido no banco contra UPDATE e DELETE" do
    log
    expect { described_class.update_all(area: "outra") }.to raise_error(ActiveRecord::StatementInvalid, /somente inserção/)
  end

  it "traduz o tipo de registros auditados antes de mudarem de nome" do
    log = described_class.create!(action: "update", area: "financeiro", auditable_type: "Invoice", changeset: { "issued_on" => [ nil, "2026-09-08" ] })
    expect(log.auditable_type_name).to eq("Nota fiscal")
    expect(log.readable_changes).to eq([ [ "Data de emissão", nil, "2026-09-08" ] ])
  end

  it "valida o tipo de evento" do
    expect(described_class.new(action: "outro", area: "acesso")).not_to be_valid
  end
end
