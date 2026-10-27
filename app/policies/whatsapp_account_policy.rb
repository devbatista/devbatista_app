# Conectar, reconfigurar e remover números é configuração da integração: exige nível "full"
# na área WhatsApp (na v1, só o administrador tem a área).
class WhatsappAccountPolicy < ApplicationPolicy
  area "whatsapp"

  def create?
    user.can_manage?(area)
  end

  def update?
    create?
  end
end
