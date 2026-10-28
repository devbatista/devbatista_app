# Mensagens seguem a matriz da área WhatsApp: quem lê vê as conversas e a mídia; enviar e tentar
# de novo exigem escrita.
class WhatsappMessagePolicy < ApplicationPolicy
  area "whatsapp"

  def retry?
    create?
  end

  def media?
    show?
  end
end
