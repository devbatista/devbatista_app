# Cada usuário só vê e marca as próprias notificações.
class NotificationPolicy < ApplicationPolicy
  def index? = true
  def update? = record.user_id == user.id

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(user: user)
    end
  end
end
