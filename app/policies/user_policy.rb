class UserPolicy < ApplicationPolicy
  area "administracao"

  # Ninguém exclui usuário: ele é desativado e continua nos registros históricos.
  def destroy?
    false
  end

  def deactivate?
    user.can_manage?(area) && record != user
  end

  # Qualquer perfil troca a própria senha, e só a própria.
  def change_password?
    record == user
  end
end
