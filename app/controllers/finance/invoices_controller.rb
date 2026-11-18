module Finance
  # Faturas ao cliente (docs/specs/faturas). A lista mostra no topo as receitas em aberto ainda sem
  # fatura, por cliente; a fatura nasce como rascunho, é emitida (número e conteúdo travados) e
  # segue para envio, pagamento ou cancelamento.
  class InvoicesController < ApplicationController
    MEMBER_ACTIONS = %i[show edit update destroy issue pdf new_delivery deliver new_payment pay new_cancellation cancel].freeze
    READ_ACTIONS = %w[show pdf].freeze

    before_action :set_invoice, only: MEMBER_ACTIONS

    def index
      authorize Invoice
      base = policy_scope(Invoice)
      today = Date.current
      @kpis = {
        open: base.awaiting_payment(today).sum(:total_cents), open_count: base.awaiting_payment(today).count,
        overdue: base.overdue(today).sum(:total_cents), overdue_count: base.overdue(today).count,
        paid_month: base.paid.where(paid_on: today.all_month).sum(:total_cents), paid_month_count: base.paid.where(paid_on: today.all_month).count,
        draft_count: base.draft.count
      }
      @unbilled = unbilled_by_company
      @counts = base.group(:status).count.merge("overdue" => base.overdue(today).count)
      scope = base.joins(:company).includes(:company, :contact)
      scope = case params[:status]
      when "overdue" then scope.overdue(today)
      when "issued" then scope.awaiting_payment(today)
      when *Invoice.statuses.keys then scope.where(status: params[:status])
      else scope
      end
      scope = scope.where(company_id: params[:empresa]) if params[:empresa].present?
      scope = scope.search(params[:q]) if params[:q].present?
      scope = apply_sort(scope, {
        "recentes" => [ "Mais recentes", ->(s) { s.order(Arel.sql("invoices.year DESC NULLS FIRST, invoices.number DESC NULLS FIRST"), created_at: :desc) } ],
        "vencimento" => [ "Vencimento", ->(s) { s.order(:due_on, :created_at) } ],
        "cliente" => [ "Cliente", ->(s) { s.order("companies.trade_name", :due_on) } ],
        "valor" => [ "Maior valor", ->(s) { s.order(total_cents: :desc) } ]
      })
      @invoices, @pager = paginate(scope)
      @companies = Company.where(id: Invoice.select(:company_id)).by_name.select(:id, :trade_name)
    end

    def show
      @history = AuditLog.where(auditable: @invoice).includes(:user).recent.limit(20)
      @documents = @invoice.documents.includes(:uploaded_by, file_attachment: :blob).recent
    end

    def new
      company = Company.find_by(id: params[:empresa])
      @invoice = authorize Invoice.new(company: company)
      return unless company

      preselected = billable(company).where(status: %w[pending overdue]).by_due.to_a
      @invoice.receivable_ids_for_items = preselected.map(&:id)
      @invoice.due_on = suggested_due_on(preselected)
    end

    def create
      @invoice = authorize Invoice.new(company_id: invoice_params[:company_id])
      @invoice.assign_attributes(invoice_params.except(:company_id))
      if @invoice.save
        redirect_to @invoice, notice: "Rascunho da fatura de #{@invoice.company.trade_name} criado. Confira e emita."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      redirect_to @invoice, alert: "Fatura #{@invoice.status_label.downcase} não pode mais ser editada." unless @invoice.editable?
    end

    def update
      return redirect_to(@invoice, alert: "Fatura #{@invoice.status_label.downcase} não pode mais ser editada.") unless @invoice.editable?

      if @invoice.update(invoice_params.except(:company_id))
        redirect_to @invoice, notice: "Rascunho atualizado."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      return redirect_to(@invoice, alert: "Só rascunhos podem ser excluídos. Para tirar uma fatura emitida da cobrança, cancele-a.") unless @invoice.draft?

      @invoice.destroy!
      redirect_to invoices_path, notice: "Rascunho excluído.", status: :see_other
    end

    def issue
      @invoice.issue!
      redirect_to @invoice, notice: "Fatura #{@invoice.code} emitida. Agora é só enviar ao cliente."
    rescue ActiveRecord::RecordInvalid => e
      redirect_to @invoice, alert: e.record.errors.full_messages.to_sentence.presence || "Não foi possível emitir a fatura."
    end

    # PDF gerado na hora (o enviado por e-mail fica em Documentos).
    def pdf
      pdf = InvoicePdf.new(@invoice, view_url: (invoice_view_url(@invoice.generate_token_for(:client_view)) unless @invoice.draft?))
      send_data pdf.render, type: "application/pdf", disposition: params[:baixar] ? "attachment" : "inline", filename: pdf.filename
    end

    def new_delivery
      @delivery = InvoiceDelivery.new(invoice: @invoice, user: current_user)
    end

    def deliver
      @delivery = InvoiceDelivery.new(invoice: @invoice, user: current_user,
                                      **params.expect(delivery: %i[to cc subject message copy_me]).to_h.symbolize_keys)
      if @delivery.save
        redirect_to @invoice, notice: "Fatura enviada para #{@delivery.recipients.to_sentence}. O PDF enviado ficou em Documentos."
      else
        render :new_delivery, status: :unprocessable_entity
      end
    end

    def new_payment
      redirect_to @invoice, alert: "Só fatura emitida recebe pagamento." unless @invoice.issued?
    end

    def pay
      return redirect_to(@invoice, alert: "Só fatura emitida recebe pagamento.") unless @invoice.issued?

      payment = params.expect(payment: %i[paid_on notes])
      if payment[:paid_on].blank?
        @invoice.errors.add(:paid_on, "precisa ser informada")
        return render(:new_payment, status: :unprocessable_entity)
      end
      @invoice.register_payment!(paid_on: payment[:paid_on], notes: payment[:notes])
      redirect_to @invoice, notice: "Pagamento da fatura #{@invoice.code} registrado em #{I18n.l(@invoice.paid_on)}; as receitas dela estão pagas."
    rescue ActiveRecord::RecordInvalid => e
      @invoice.errors.add(:base, e.record.errors.full_messages.to_sentence) unless e.record == @invoice
      render :new_payment, status: :unprocessable_entity
    end

    def new_cancellation
      redirect_to @invoice, alert: "Só fatura emitida pode ser cancelada." unless @invoice.issued?
    end

    def cancel
      return redirect_to(@invoice, alert: "Só fatura emitida pode ser cancelada.") unless @invoice.issued?

      @invoice.cancel!(params.dig(:cancellation, :reason))
      redirect_to @invoice, notice: "Fatura #{@invoice.code} cancelada. As receitas voltaram para a lista de receitas sem fatura."
    rescue ActiveRecord::RecordInvalid
      @invoice.status = "issued"
      render :new_cancellation, status: :unprocessable_entity
    end

    private

    def set_invoice
      @invoice = Invoice.find(params[:id])
      authorize @invoice, READ_ACTIONS.include?(action_name) ? :show? : (action_name == "destroy" ? :destroy? : :update?)
    end

    def invoice_params
      params.expect(invoice: [ :company_id, :contact_id, :due_on, :client_notes, :notes, receivable_ids_for_items: [] ])
    end

    # Receitas que ainda podem entrar numa fatura do cliente: em aberto, sem fatura emitida e fora
    # de outro rascunho.
    def billable(company, invoice: nil)
      in_drafts = InvoiceItem.joins(:invoice).merge(Invoice.draft).where.not(invoice_id: invoice&.id).select(:receivable_id)
      Invoice.billable_receivables(company.id, invoice: invoice).where.not(id: in_drafts)
    end
    helper_method :billable

    # Vencimento sugerido: o da receita que vence primeiro, mas nunca antes de hoje + 3 dias.
    def suggested_due_on(receivables)
      [ receivables.map(&:due_on).min, Date.current + 3 ].compact.max
    end

    def unbilled_by_company
      in_drafts = InvoiceItem.joins(:invoice).merge(Invoice.draft).select(:receivable_id)
      rows = policy_scope(Receivable).where(status: %w[pending overdue], invoice_id: nil).where.not(id: in_drafts)
                                     .group(:company_id).pluck(:company_id, Arel.sql("COUNT(*)"), Arel.sql("SUM(amount_cents)"), Arel.sql("MIN(due_on)"))
      companies = Company.where(id: rows.map(&:first)).index_by(&:id)
      rows.map { |id, count, total, due| { company: companies[id], count: count, total: total, due_on: due } }.sort_by { |r| r[:due_on] }
    end
  end
end
