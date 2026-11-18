require "rails_helper"

RSpec.describe "Faturas" do
  let(:financeiro) { create(:user, :financeiro) }
  let(:company) { create(:company, trade_name: "Empresa ACME") }
  let!(:contact) { create(:contact, company: company, primary: true, name: "Maria Souza", email: "maria@acme.com.br", whatsapp: "(11) 98765-4321") }

  before { Setting[:pix_key] = "12345678000195" }

  def issued_invoice(**attrs)
    create(:invoice, :issued, company: company, **attrs)
  end

  it "lista as receitas sem fatura por cliente e as faturas por situação" do
    create(:receivable, company: company, description: "Hospedagem — Novembro/2026", amount_cents: 30_000)
    issued_invoice
    sign_in financeiro
    get invoices_path
    expect(response.body).to include("Receitas sem fatura", "Empresa ACME", "Criar fatura", "FAT-#{Date.current.year}-0001", "Emitida")
    get invoices_path(status: "overdue")
    expect(response.body).not_to include("FAT-#{Date.current.year}-0001")
  end

  it "cria o rascunho com as receitas escolhidas e emite" do
    a = create(:receivable, company: company, description: "Hospedagem", amount_cents: 30_000)
    b = create(:receivable, company: company, description: "Suporte", amount_cents: 90_000)
    sign_in financeiro
    get new_invoice_path(empresa: company.id)
    expect(response.body).to include("Hospedagem", "Suporte", "Criar rascunho")
    post invoices_path, params: { invoice: { company_id: company.id, contact_id: contact.id, due_on: Date.current + 7,
                                             receivable_ids_for_items: [ "", a.id, b.id ], client_notes: "Serviços de novembro" } }
    invoice = Invoice.last
    expect(response).to redirect_to(invoice_path(invoice))
    expect(invoice).to have_attributes(total_cents: 120_000, status: "draft", client_notes: "Serviços de novembro")
    get edit_invoice_path(invoice)
    expect(response.body).to include("Editar rascunho", "Salvar rascunho")
    patch issue_invoice_path(invoice)
    expect(invoice.reload).to be_issued
    get invoice_path(invoice)
    expect(response.body).to include(invoice.code, "Registrar pagamento", "Copiar link", "Serviços de novembro")
  end

  it "recusa rascunho sem receita" do
    sign_in financeiro
    post invoices_path, params: { invoice: { company_id: company.id, due_on: Date.current + 7, receivable_ids_for_items: [ "" ] } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("Escolha ao menos uma receita")
  end

  it "gera o PDF da fatura" do
    invoice = issued_invoice
    sign_in financeiro
    get pdf_invoice_path(invoice)
    expect(response.media_type).to eq("application/pdf")
    expect(response.body).to start_with("%PDF")
  end

  it "envia por e-mail com o PDF, guarda em Documentos e marca a data de envio" do
    invoice = issued_invoice
    sign_in financeiro
    get delivery_invoice_path(invoice)
    expect(response.body).to include("maria@acme.com.br", "Fatura #{invoice.code}")
    expect do
      post delivery_invoice_path(invoice), params: { delivery: { to: "maria@acme.com.br", subject: "Fatura", message: "Segue a fatura.", copy_me: "0" } }
    end.to have_enqueued_mail(InvoiceMailer, :client)
    expect(invoice.reload.sent_at).to be_present
    expect(invoice.documents.last).to have_attributes(kind: "invoice")
    expect(invoice.documents.last.file.content_type).to eq("application/pdf")
  end

  it "registra o pagamento integral e oferece registrar a nota fiscal" do
    invoice = issued_invoice
    sign_in financeiro
    get payment_invoice_path(invoice)
    expect(response.body).to include("Pagamento integral", invoice.code)
    patch payment_invoice_path(invoice), params: { payment: { paid_on: Date.current, notes: "Pix" } }
    expect(invoice.reload).to be_paid
    expect(invoice.receivables.pluck(:status).uniq).to eq([ "paid" ])
    get invoice_path(invoice)
    expect(response.body).to include("Registrar nota fiscal")
    get new_fiscal_invoice_path(fatura: invoice.id)
    expect(response.body).to include(invoice.items.first.description)
  end

  it "cancela com motivo e devolve as receitas" do
    invoice = issued_invoice
    sign_in financeiro
    patch cancel_invoice_path(invoice), params: { cancellation: { reason: "" } }
    expect(response).to have_http_status(:unprocessable_entity)
    patch cancel_invoice_path(invoice), params: { cancellation: { reason: "Valor errado" } }
    expect(invoice.reload).to be_cancelled
    expect(Receivable.where(invoice_id: invoice.id)).to be_empty
  end

  it "só exclui rascunho (com permissão de exclusão)" do
    draft = create(:invoice, company: company)
    issued = issued_invoice
    sign_in create(:user, :admin)
    delete invoice_path(issued)
    expect(Invoice.exists?(issued.id)).to be(true)
    delete invoice_path(draft)
    expect(Invoice.exists?(draft.id)).to be(false)
  end

  it "responde 403 para quem não acessa o Financeiro" do
    sign_in create(:user, :comercial)
    get invoices_path
    expect(response).to have_http_status(:forbidden)
  end

  describe "link público" do
    it "mostra a fatura com o Pix sem login, baixa o PDF e marca visualizada" do
      invoice = issued_invoice
      token = invoice.generate_token_for(:client_view)
      get invoice_view_path(token)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(invoice.code, "Copiar código Pix", "<svg", "br.gov.bcb.pix")
      expect(invoice.reload.viewed_at).to be_present
      get invoice_view_pdf_path(token)
      expect(response.body).to start_with("%PDF")
    end

    it "mostra paga no lugar do Pix" do
      invoice = issued_invoice.tap { |i| i.register_payment!(paid_on: Date.current) }
      get invoice_view_path(invoice.generate_token_for(:client_view))
      expect(response.body).to include("Fatura paga")
      expect(response.body).not_to include("Copiar código Pix")
    end

    it "não abre rascunho nem token inválido" do
      draft = create(:invoice, company: company)
      get invoice_view_path(draft.generate_token_for(:client_view))
      expect(response).to have_http_status(:not_found)
      get invoice_view_path("invalido")
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "WhatsApp" do
    it "preenche as variáveis da fatura e o fim do botão de link" do
      invoice = issued_invoice
      template = create(:whatsapp_template, status: "approved", name: "fatura_emitida", components: [
        { "type" => "BODY", "text" => "Olá, {{nome}}! A fatura {{fatura}} de {{valor}} vence em {{vencimento}}." },
        { "type" => "BUTTONS", "buttons" => [ { "type" => "URL", "text" => "Ver fatura", "url" => "https://admin.devbatista.com/f/{{1}}" } ] }
      ])
      person = Whatsapp::TemplateFields.person(contact).merge(Whatsapp::TemplateFields.invoice(invoice, link: "https://x/f/tok", token: "tok"))
      defaults = Whatsapp::TemplateFields.new(template).to_h(person: person)[:defaults]
      expect(defaults[:body]).to eq([ "Maria", invoice.code, ApplicationController.helpers.brl(invoice.total_cents), I18n.l(invoice.due_on, format: '%d/%m/%Y') ])
      expect(defaults[:buttons]).to eq("0" => "tok")
    end

    it "envia o template com o PDF da fatura no cabeçalho de documento e marca enviada" do
      invoice = issued_invoice
      account = create(:whatsapp_account, status: "connected")
      template = create(:whatsapp_template, account: account, components: [
        { "type" => "HEADER", "format" => "DOCUMENT" },
        { "type" => "BODY", "text" => "Olá, {{1}}! Segue a fatura." }
      ])
      sign_in create(:user, :admin)
      post whatsapp_conversation_start_path, params: { contact_id: contact.id, fatura: invoice.id, conta: account.id, template_id: template.id, values: { body: [ "Maria" ] } }
      expect(response).to redirect_to(invoice_path(invoice))
      message = WhatsappMessage.last
      expect(message.media.filename.to_s).to eq("fatura-#{invoice.code}.pdf")
      expect(message.media_mime_type).to eq("application/pdf")
      expect(invoice.reload.sent_at).to be_present
    end

    it "abre o Iniciar conversa com a fatura" do
      invoice = issued_invoice
      sign_in create(:user, :admin)
      get new_whatsapp_conversation_start_path(contact_id: contact.id, fatura: invoice.id)
      expect(response.body).to include("Fatura <b class=\"strong\">#{invoice.code}</b>", "name=\"fatura\"")
    end
  end
end
