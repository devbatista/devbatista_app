# Contas a pagar e despesas recorrentes ligadas ao serviço externo (RF 26) e chamado ligado à
# aplicação afetada.
class LinkFinanceAndSupportToTechnology < ActiveRecord::Migration[8.1]
  def change
    add_reference :payables, :external_service, foreign_key: true
    add_reference :recurring_expenses, :external_service, foreign_key: true
    add_reference :tickets, :app, foreign_key: true
  end
end
