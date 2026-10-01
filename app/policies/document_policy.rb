class DocumentPolicy < ApplicationPolicy
  area "documentos"

  # Quem enviou também pode excluir o próprio arquivo; os demais precisam de "Total".
  def destroy?
    super || (user.can_write?(area) && record.respond_to?(:uploaded_by_id) && record.uploaded_by_id == user.id)
  end
end
