class UserPolicy < ApplicationPolicy
  area "administracao"

  # Ninguém exclui usuário: ele é desativado e continua nos registros históricos.
  def destroy?
    false
  end

  def deactivate?
    user.can_manage?(area) && record != user
  end
end
