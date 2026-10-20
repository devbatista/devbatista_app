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

  it "aceita o CNPJ da empresa em branco, mas recusa um inválido" do
    described_class[:company_cnpj] = ""
    expect(described_class[:company_cnpj]).to eq("")
    expect { described_class[:company_cnpj] = "11111111111111" }.to raise_error(ActiveRecord::RecordInvalid, /CNPJ/)
  end

  it "aceita WhatsApp com DDD, fixo ou celular, e formata para exibir" do
    described_class[:company_whatsapp] = "11987654321"
    expect(described_class.format_phone(described_class[:company_whatsapp])).to eq("(11) 98765-4321")
    expect(described_class.format_phone("1134567890")).to eq("(11) 3456-7890")
    expect { described_class[:company_whatsapp] = "98765432" }.to raise_error(ActiveRecord::RecordInvalid, /WhatsApp/)
  end

  it "recusa chave desconhecida" do
    expect { described_class[:qualquer] = 1 }.to raise_error(ActiveRecord::RecordInvalid)
  end
end
