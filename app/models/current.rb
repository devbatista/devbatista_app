# Dados da requisição atual, usados pela auditoria.
class Current < ActiveSupport::CurrentAttributes
  attribute :user, :ip_address
end
