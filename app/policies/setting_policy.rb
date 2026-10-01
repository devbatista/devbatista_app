class SettingPolicy < ApplicationPolicy
  area "administracao"

  def update?
    user.can_manage?(area)
  end
end
