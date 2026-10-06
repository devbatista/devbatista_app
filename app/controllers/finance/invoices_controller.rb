module Finance
  # Notas fiscais emitidas fora do sistema (RF 28). A lista "Pendentes de emissão" mostra as
  # receitas da competência que ainda não têm nota.
  class InvoicesController < ApplicationController
    include FinancePeriod

    before_action :set_invoice, only: %i[edit update destroy file]

    def index
      authorize Invoice
      set_period(back: 12, forward: 0)
      base = policy_scope(Invoice).where(competence: @range)
      revenues = Receivable.not_cancelled.where(competence: @range)
      @pending = revenues.where(invoice_id: nil).where.not(id: Invoice.issued.joins(:receivables).select("receivables.id"))
                         .includes(:company).order(:due_on).to_a
      @kpis = {
        to_invoice: revenues.sum(:amount_cents), to_invoice_count: revenues.count,
        issued: base.issued.sum(:amount_cents), issued_count: base.issued.count,
        pending: @pending.sum(&:amount_cents) + base.pending.sum(:amount_cents), pending_count: @pending.size + base.pending.count,
        cancelled: base.cancelled.sum(:amount_cents), cancelled_count: base.cancelled.count
      }
      scope = base.joins(:company).includes(:company, :receivables, files_attachments: :blob)
      @counts = base.group(:status).count
      scope = scope.where(status: params[:status]) if Invoice.statuses.key?(params[:status])
      scope = scope.where(company_id: params[:empresa]) if params[:empresa].present?
      scope = scope.search(params[:q]) if params[:q].present?
      scope = apply_sort(scope, {
        "emissao" => [ "Emissão mais recente", ->(s) { s.order(Arel.sql("invoices.issued_on DESC NULLS FIRST"), id: :desc) } ],
        "numero" => [ "Número", ->(s) { s.order(Arel.sql("invoices.number DESC NULLS FIRST")) } ],
        "cliente" => [ "Cliente", ->(s) { s.order("companies.trade_name") } ]
      })
      @invoices, @pager = paginate(scope)
      @companies = Company.where(id: Invoice.select(:company_id)).by_name.select(:id, :trade_name)
    end

    def new
      receivable = Receivable.find_by(id: params[:receita])
      @invoice = authorize Invoice.new(company: receivable&.company || Company.find_by(id: params[:empresa]), status: "issued",
                                       competence: receivable&.competence || Date.current.beginning_of_month,
                                       amount_cents: receivable&.amount_cents, description: receivable&.description, issued_on: Date.current)
      @invoice.receivable_ids = [ receivable.id ] if receivable
    end

    def create
      @invoice = authorize Invoice.new(invoice_params)
      if @invoice.save
        redirect_to invoices_path(periodo: @invoice.competence_month), notice: "#{@invoice.code} registrada para #{@invoice.company.trade_name}."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    # Arquivos novos entram junto dos que a nota já tem.
    def update
      attrs = invoice_params
      new_files = attrs.delete(:files)
      @invoice.assign_attributes(attrs)
      @invoice.files.attach(new_files) if new_files.present?
      if @invoice.save
        redirect_to invoices_path(periodo: @invoice.competence_month), notice: "#{@invoice.code} atualizada."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @invoice.destroy!
      redirect_to invoices_path, notice: "Nota excluída.", status: :see_other
    end

    # Abre o PDF ou o XML da nota (URL assinada e temporária do Active Storage).
    def file
      attachment = @invoice.files.find(params[:file_id])
      redirect_to rails_blob_path(attachment, disposition: "inline"), allow_other_host: false
    end

    private

    def set_invoice
      @invoice = Invoice.find(params[:id])
      authorize @invoice, action_name == "file" ? :show? : "#{action_name}?"
    end

    def invoice_params
      permitted = params.expect(invoice: [ :company_id, :number, :competence_month, :amount, :issued_on, :status, :description, :url, :notes,
                                           { receivable_ids: [], files: [] } ])
      permitted[:receivable_ids] = Array(permitted[:receivable_ids]).compact_blank if permitted.key?(:receivable_ids)
      permitted.delete(:files) if Array(permitted[:files]).compact_blank.empty?
      permitted
    end
  end
end
