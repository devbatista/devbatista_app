# Templates seguem a matriz da área WhatsApp: quem lê vê a lista e a prévia; criar, editar e
# sincronizar exigem escrita; excluir exige "full" (na v1, só o administrador tem a área).
class WhatsappTemplatePolicy < ApplicationPolicy
  area "whatsapp"

  def sync?
    create?
  end
end
