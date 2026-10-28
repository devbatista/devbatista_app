module ApplicationCable
  # Conexão do ActionCable autenticada pela sessão do Devise: sem login, a conexão é recusada.
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = env["warden"]&.user || reject_unauthorized_connection
      reject_unauthorized_connection unless current_user.active?
    end
  end
end
