require "rails_helper"

RSpec.describe "E-mails" do
  let(:user) { create(:user, name: "Ana Souza", email: "ana@devbatista.com") }

  def html(mail) = mail.html_part.body.decoded
  def text(mail) = mail.text_part.body.decoded

  describe NotificationMailer do
    let(:notification) do
      Notification.create!(user: user, kind: "receivable_overdue", level: "crit", area: "financeiro",
                           title: "Título da Acme vencido", path: "/receivables")
    end
    let(:mail) { described_class.alert(notification) }

    it "sai do remetente configurado, com o layout padrão em HTML e texto" do
      expect(mail.from).to eq([ "nao-responda@devbatista.com" ])
      expect(mail.subject).to eq("[Admin DevBatista] Título da Acme vencido")
      expect(html(mail)).to include("Pagamentos vencidos", "Crítico", "Abrir no sistema", "E-mail automático do")
      expect(text(mail)).to include("Título da Acme vencido", "http://example.com/receivables", "Não responda.")
    end
  end

  describe "redefinição de senha (Devise)" do
    it "usa o layout e o remetente do ApplicationMailer" do
      user.update_columns(sign_in_count: 3)
      mail = Devise::Mailer.reset_password_instructions(user, "token")

      expect(mail.from).to eq([ "nao-responda@devbatista.com" ])
      expect(mail.subject).to eq("[Admin DevBatista] Defina sua senha de acesso")
      expect(html(mail)).to include("Redefinir senha", "Criar nova senha", "reset_password_token=token", "2 horas", "E-mail automático do")
    end

    it "dá boas-vindas a quem ainda não entrou (convite de usuário novo)" do
      mail = Devise::Mailer.reset_password_instructions(user, "token")

      expect(html(mail)).to include("Bem-vindo ao Admin DevBatista", "Definir minha senha", user.role.name)
      expect(text(mail)).to include("BEM-VINDO AO ADMIN DEVBATISTA")
    end
  end
end
