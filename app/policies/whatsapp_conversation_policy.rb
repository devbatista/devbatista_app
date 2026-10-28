# Conversas seguem a matriz da área WhatsApp: quem lê abre a conversa (o que também a marca como
# lida), pagina as mensagens e vê o painel. Vincular, criar lead e desvincular exigem escrita; os
# dados do CRM no painel seguem a área de cada cadastro (Comercial e Clientes).
class WhatsappConversationPolicy < ApplicationPolicy
  area "whatsapp"

  def read?
    show?
  end

  def messages?
    show?
  end

  def panel?
    show?
  end

  def link?
    update?
  end
end
