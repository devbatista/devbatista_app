class AuditLogPolicy < ApplicationPolicy
  area "administracao"

  def create? = false
  def update? = false
  def destroy? = false
end
