class BillingConnectionPolicy < ApplicationPolicy
  area "financeiro"

  def sync?
    update?
  end
end
