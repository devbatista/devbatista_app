require "rails_helper"

RSpec.describe Invoice do
  let(:company) { create(:company) }
  let!(:contact) { create(:contact, company: company, primary: true, email: "financeiro@cliente.com.br") }

  def receivable(**attrs)
    create(:receivable, company: company, **attrs)
  end

  def draft(*receivables, due_on: Date.current + 7)
    invoice = described_class.new(company: company, due_on: due_on)
    invoice.receivable_ids_for_items = receivables.map(&:id)
    invoice.save!
    invoice
  end

  it "agrupa receitas do cliente num rascunho, com cópia de cada uma e o contato principal" do
    a = receivable(description: "Hospedagem", amount_cents: 30_000)
    b = receivable(description: "Suporte", amount_cents: 90_000)
    invoice = draft(a, b)
    expect(invoice).to have_attributes(status: "draft", code: "Rascunho", total_cents: 120_000, contact: contact, number: nil)
    expect(invoice.items.map(&:description)).to eq(%w[Hospedagem Suporte])
    expect(a.reload.invoice_id).to be_nil
  end

  it "não aceita receita de outro cliente, paga ou cancelada" do
    other = create(:receivable)
    paid = receivable(paid_on: Date.current)
    cancelled = receivable.tap { |r| r.cancel!("x") }
    invoice = described_class.new(company: company, due_on: Date.current + 7)
    invoice.receivable_ids_for_items = [ other.id, paid.id, cancelled.id ]
    expect(invoice).not_to be_valid
    expect(invoice.errors[:base]).to include("Escolha ao menos uma receita para a fatura")
  end

  it "na emissão dá o número do ano e leva as receitas para o vencimento da fatura" do
    late = receivable(due_on: Date.current - 3)
    expect(late.reload).to be_overdue
    invoice = draft(late, due_on: Date.current + 10)
    invoice.issue!
    expect(invoice).to have_attributes(status: "issued", code: "FAT-#{Date.current.year}-0001", issued_on: Date.current)
    expect(late.reload).to have_attributes(invoice_id: invoice.id, due_on: Date.current + 10, status: "pending")
    expect(draft(receivable).tap(&:issue!).code).to eq("FAT-#{Date.current.year}-0002")
  end

  it "não emite se a receita entrou em outra fatura emitida" do
    shared = receivable
    first = draft(shared)
    second = draft(shared)
    first.issue!
    expect { second.issue! }.to raise_error(ActiveRecord::RecordInvalid, /já está em outra fatura/)
    expect(second.reload).to be_draft
  end

  it "trava valor, cliente e cancelamento da receita enquanto a fatura está emitida" do
    r = receivable
    draft(r).issue!
    expect(r.reload.update(amount_cents: 1)).to be(false)
    expect(r.errors[:base].first).to match(/está na fatura FAT-/)
    expect { r.reload.cancel!("x") }.to raise_error(ActiveRecord::RecordInvalid)
    expect(r.reload.update(notes: "ok")).to be(true)
  end

  it "registra o pagamento integral: a fatura e todas as receitas pagas na mesma data" do
    a = receivable(amount_cents: 30_000)
    b = receivable(amount_cents: 90_000)
    invoice = draft(a, b).tap(&:issue!)
    invoice.register_payment!(paid_on: Date.current - 1)
    expect(invoice).to be_paid
    expect([ a.reload, b.reload ].map { |r| [ r.status, r.paid_on, r.paid_amount_cents ] })
      .to eq([ [ "paid", Date.current - 1, 30_000 ], [ "paid", Date.current - 1, 90_000 ] ])
  end

  it "ao cancelar, as receitas voltam a ficar sem fatura e os itens continuam no documento" do
    r = receivable
    invoice = draft(r).tap(&:issue!)
    expect { invoice.cancel!("") }.to raise_error(ActiveRecord::RecordInvalid)
    invoice.reload.cancel!("Valor errado")
    expect(invoice).to have_attributes(status: "cancelled", cancellation_reason: "Valor errado")
    expect(invoice.items.count).to eq(1)
    expect(r.reload.invoice_id).to be_nil
    expect(draft(r).tap(&:issue!)).to be_issued
  end

  it "fica Vencida (calculado) depois do vencimento, só enquanto emitida" do
    invoice = draft(receivable, due_on: Date.current + 2).tap(&:issue!)
    expect(invoice.display_status_label).to eq("Emitida")
    expect(invoice.display_status_label(Date.current + 3)).to eq("Vencida")
    expect(described_class.overdue(Date.current + 3)).to include(invoice)
    expect(invoice.days_late(Date.current + 5)).to eq(3)
  end

  it "o link público acha a fatura pelo token" do
    invoice = draft(receivable)
    expect(described_class.find_by_token_for(:client_view, invoice.generate_token_for(:client_view))).to eq(invoice)
  end

  it "a rotina diária avisa uma vez pela fatura vencida, em vez de por receita" do
    create(:user, :financeiro)
    a = receivable
    b = receivable
    invoice = draft(a, b, due_on: Date.current + 1).tap(&:issue!)
    loose = receivable(due_on: Date.current)
    RecurrenceRoutine.new(Date.current + 2).run!
    expect(Notification.where(notifiable: invoice).count).to be_positive
    expect(Notification.where(notifiable: [ a, b ])).to be_empty
    expect(Notification.where(notifiable: loose)).to exist
  end
end

RSpec.describe PixPayload do
  before do
    Setting[:pix_key] = "12.345.678/0001-90"
    Setting[:pix_receiver_name] = "DevBatista Tecnologia"
    Setting[:pix_receiver_city] = "São Paulo"
  end

  it "monta o BR Code estático com valor, identificador e CRC16" do
    pix = described_class.new(amount_cents: 380_000, txid: "FAT-2026-0001")
    code = pix.to_s
    expect(code).to start_with("000201")
    expect(code).to include("0014br.gov.bcb.pix0114123456780001905204000053039865407" + "3800.00", "5921DEVBATISTA TECNOLOGIA6009SAO PAULO", "0511FAT20260001")
    crc = code[-4..]
    expect(described_class.new(amount_cents: 0, txid: "x").send(:crc16, code[0...-4])).to eq(crc)
    expect(pix.qr_svg).to include("<svg")
  end

  it "confere o CRC com o exemplo do Banco Central" do
    example = "00020126580014br.gov.bcb.pix0136123e4567-e12b-12d1-a456-4266554400005204000053039865802BR5913Fulano de Tal6008BRASILIA62070503***6304"
    expect(described_class.new(amount_cents: 0, txid: "x").send(:crc16, example)).to eq("1D3D")
  end

  it "normaliza telefone com +55 e e-mail em minúsculas" do
    expect(described_class.new(amount_cents: 1, txid: "a", key: "(11) 98765-4321").key).to eq("+5511987654321")
    expect(described_class.new(amount_cents: 1, txid: "a", key: "Pix@DevBatista.com").key).to eq("pix@devbatista.com")
  end

  it "fica indisponível sem chave" do
    Setting[:pix_key] = ""
    expect(described_class.new(amount_cents: 1, txid: "a")).not_to be_available
    expect(described_class.configured?).to be(false)
  end
end
