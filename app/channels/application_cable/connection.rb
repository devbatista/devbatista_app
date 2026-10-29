module ApplicationCable
  # Conexão do ActionCable autenticada pela sessão do Devise: sem login, a conexão é recusada.
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = session_user || reject_unauthorized_connection
      reject_unauthorized_connection unless current_user.active?
    end

    private

    # Sessão expirada: o Devise (timeoutable) faz throw :warden, que nas requisições normais o
    # middleware do Warden captura. Aqui não há middleware: vira conexão recusada, e o navegador para
    # de tentar até a próxima página (que leva ao login).
    def session_user
      user = nil
      catch(:warden) { user = env["warden"]&.user }
      user
    end
  end
end
