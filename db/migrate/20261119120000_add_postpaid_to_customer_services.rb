# Serviço pós-pago: o vencimento cobra o mês anterior (serviço de outubro pago em 06/11). A
# rotina de recorrências passa a gravar a competência como o mês antes do vencimento.
class AddPostpaidToCustomerServices < ActiveRecord::Migration[8.1]
  def change
    add_column :customer_services, :postpaid, :boolean, null: false, default: false
  end
end
