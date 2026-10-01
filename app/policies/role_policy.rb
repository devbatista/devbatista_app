class RolePolicy < ApplicationPolicy
  area "administracao"

  def update?
    user.can_manage?(area) && !record.admin?
  end

  def create? = false
  def destroy? = false
end
