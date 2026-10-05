# Horas trabalhadas: no nível "Próprio" o usuário só vê e edita os próprios lançamentos
# (o Scope da ApplicationPolicy filtra por user_id).
class TimeEntryPolicy < ApplicationPolicy
  area "horas"

  # Quem lançou também pode excluir o próprio lançamento; os demais precisam de "Total".
  def destroy?
    super || (user.can_write?(area) && owns_record?)
  end

  # Só quem tem "Total" lança horas para outra pessoa.
  def assign_user?
    user.can_manage?(area)
  end
end
