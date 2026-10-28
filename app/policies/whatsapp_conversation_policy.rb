# Conversas seguem a matriz da área WhatsApp: quem lê abre a conversa (o que também a marca como
# lida) e pagina as mensagens.
class WhatsappConversationPolicy < ApplicationPolicy
  area "whatsapp"

  def read?
    show?
  end

  def messages?
    show?
  end
end
