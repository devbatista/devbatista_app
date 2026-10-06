module Customers
  class ContactsController < ApplicationController
    before_action :set_contact, only: %i[edit update destroy make_primary]

    def index
      authorize Contact
      scope = policy_scope(Contact).joins(:company).includes(:company)
      @counts = { "todos" => scope.count, "principal" => scope.primaries.count }
      @counts["demais"] = @counts["todos"] - @counts["principal"]
      scope = scope.where(primary: params[:tipo] == "principal") if params[:tipo].in?(%w[principal demais])
      scope = scope.where(company_id: params[:empresa]) if params[:empresa].present?
      scope = scope.search(params[:q]) if params[:q].present?
      scope = apply_sort(scope, {
        "empresa" => [ "Empresa", ->(s) { s.order("companies.trade_name", primary: :desc, name: :asc) } ],
        "nome" => [ "Nome (A–Z)", ->(s) { s.order(:name) } ]
      })
      @contacts, @pager = paginate(scope)
      @companies = Company.by_name.select(:id, :trade_name)
      @kpis = {
        total: Contact.count,
        companies: Contact.distinct.count(:company_id),
        primaries: Contact.primaries.count,
        without_primary: Company.where.not(id: Contact.primaries.select(:company_id)).order(:trade_name).to_a,
        whatsapp: Contact.where.not(whatsapp: [ nil, "" ]).count
      }
    end

    def new
      @contact = authorize Contact.new(company_id: params[:empresa])
    end

    def create
      @contact = authorize Contact.new(contact_params)
      if @contact.save
        redirect_to return_path(@contact), notice: "Contato cadastrado."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @contact.update(contact_params)
        redirect_to return_path(@contact), notice: "Contato atualizado."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def make_primary
      @contact.update!(primary: true)
      redirect_to return_path(@contact), notice: "#{@contact.name} agora é o contato principal de #{@contact.company.trade_name}."
    end

    def destroy
      @contact.destroy!
      redirect_to return_path(@contact), notice: "Contato excluído.", status: :see_other
    end

    private

    def set_contact
      @contact = authorize Contact.find(params[:id]), (action_name == "make_primary" ? :update? : nil)
    end

    def contact_params
      params.expect(contact: %i[company_id name position phone whatsapp email primary notes])
    end

    # Volta para a Visão 360º quando a ação começou lá.
    def return_path(contact)
      params[:voltar] == "empresa" ? company_path(contact.company, aba: "resumo") : contacts_path
    end
  end
end
