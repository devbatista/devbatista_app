# Centro de custo de despesas: uma área interna (lista em Configurações) ou um cliente.
# Com cliente, a despesa entra no custo direto dele (RF 24). No formulário é um select só:
#   cost_center_key = "area:Operação" ou "company:12"
module CostCenter
  extend ActiveSupport::Concern

  included do
    belongs_to :company, optional: true

    validate :cost_center_present
    validates :cost_center, inclusion: { in: ->(_) { Setting[:cost_centers] }, message: "não está na lista de centros de custo" },
                            if: -> { company_id.nil? && will_save_change_to_cost_center? }

    scope :for_company, ->(company) { where(company: company) }
  end

  class_methods do
    # Opções agrupadas para o select: áreas internas e clientes.
    def cost_center_options(extra_company = nil)
      companies = Company.where.not(status: "inactive").or(Company.where(id: extra_company)).by_name
      [ [ "Áreas internas", Setting[:cost_centers].map { |a| [ a, "area:#{a}" ] } ],
        [ "Clientes", companies.map { |c| [ c.trade_name, "company:#{c.id}" ] } ] ]
    end
  end

  def cost_center_key
    company_id ? "company:#{company_id}" : ("area:#{cost_center}" if cost_center)
  end

  def cost_center_key=(value)
    kind, id = value.to_s.split(":", 2)
    self.company_id = kind == "company" ? id.to_i : nil
    self.cost_center = kind == "area" ? id : nil
  end

  def cost_center_name
    company ? company.trade_name : cost_center
  end

  private

  def cost_center_present
    errors.add(:cost_center, "precisa ser uma área interna ou um cliente") if company_id.nil? && cost_center.blank?
  end
end
