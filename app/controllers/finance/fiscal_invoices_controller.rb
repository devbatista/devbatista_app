module Finance
  # Notas fiscais emitidas fora do sistema (RF 28). A lista "Pendentes de emissão" mostra as
  # receitas da competência que ainda não têm nota.
  class FiscalInvoicesController < ApplicationController
    include FinancePeriod

    before_action :set_fiscal_invoice, only: %i[edit update destroy file]

    def index
      authorize FiscalInvoice
      set_period(back: 12, forward: 0)
      base = policy_scope(FiscalInvoice).where(competence: @range)
      revenues = Receivable.not_cancelled.where(competence: @range)
      @pending = revenues.where(fiscal_invoice_id: nil).where.not(id: FiscalInvoice.issued.joins(:receivables).select("receivables.id"))
                         .includes(:company).order(:due_on).to_a
      @kpis = {
        to_fiscal_invoice: revenues.sum(:amount_cents), to_fiscal_invoice_count: revenues.count,
        issued: base.issued.sum(:amount_cents), issued_count: base.issued.count,
        pending: @pending.sum(&:amount_cents) + base.pending.sum(:amount_cents), pending_count: @pending.size + base.pending.count,
        cancelled: base.cancelled.sum(:amount_cents), cancelled_count: base.cancelled.count
      }
      scope = base.joins(:company).includes(:company, :receivables, files_attachments: :blob)
      @counts = base.group(:status).count
      scope = scope.where(status: params[:status]) if FiscalInvoice.statuses.key?(params[:status])
      scope = scope.where(company_id: params[:empresa]) if params[:empresa].present?
      scope = scope.search(params[:q]) if params[:q].present?
      scope = apply_sort(scope, {
        "emissao" => [ "Emissão mais recente", ->(s) { s.order(Arel.sql("fiscal_invoices.issued_on DESC NULLS FIRST"), id: :desc) } ],
        "numero" => [ "Número", ->(s) { s.order(Arel.sql("fiscal_invoices.number DESC NULLS FIRST")) } ],
        "cliente" => [ "Cliente", ->(s) { s.order("companies.trade_name") } ]
      })
      @fiscal_invoices, @pager = paginate(scope)
      @companies = Company.where(id: FiscalInvoice.select(:company_id)).by_name.select(:id, :trade_name)
    end

    def new
      receivable = Receivable.find_by(id: params[:receita])
      @fiscal_invoice = authorize FiscalInvoice.new(company: receivable&.company || Company.find_by(id: params[:empresa]), status: "issued",
                                       competence: receivable&.competence || Date.current.beginning_of_month,
                                       amount_cents: receivable&.amount_cents, description: receivable&.description, issued_on: Date.current)
      @fiscal_invoice.receivable_ids = [ receivable.id ] if receivable
    end

    def create
      @fiscal_invoice = authorize FiscalInvoice.new(fiscal_invoice_params)
      if @fiscal_invoice.save
        redirect_to fiscal_invoices_path(periodo: @fiscal_invoice.competence_month), notice: "#{@fiscal_invoice.code} registrada para #{@fiscal_invoice.company.trade_name}."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    # Arquivos novos entram junto dos que a nota já tem.
    def update
      attrs = fiscal_invoice_params
      new_files = attrs.delete(:files)
      @fiscal_invoice.assign_attributes(attrs)
      @fiscal_invoice.files.attach(new_files) if new_files.present?
      if @fiscal_invoice.save
        redirect_to fiscal_invoices_path(periodo: @fiscal_invoice.competence_month), notice: "#{@fiscal_invoice.code} atualizada."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @fiscal_invoice.destroy!
      redirect_to fiscal_invoices_path, notice: "Nota excluída.", status: :see_other
    end

    # Abre o PDF ou o XML da nota (URL assinada e temporária do Active Storage).
    def file
      attachment = @fiscal_invoice.files.find(params[:file_id])
      redirect_to rails_blob_path(attachment, disposition: "inline"), allow_other_host: false
    end

    private

    def set_fiscal_invoice
      @fiscal_invoice = FiscalInvoice.find(params[:id])
      authorize @fiscal_invoice, action_name == "file" ? :show? : "#{action_name}?"
    end

    def fiscal_invoice_params
      permitted = params.expect(fiscal_invoice: [ :company_id, :number, :competence_month, :amount, :issued_on, :status, :description, :url, :notes,
                                           { receivable_ids: [], files: [] } ])
      permitted[:receivable_ids] = Array(permitted[:receivable_ids]).compact_blank if permitted.key?(:receivable_ids)
      permitted.delete(:files) if Array(permitted[:files]).compact_blank.empty?
      permitted
    end
  end
end
