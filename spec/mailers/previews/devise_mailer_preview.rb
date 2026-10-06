# Pré-visualização em /rails/mailers (desenvolvimento).
class DeviseMailerPreview < ActionMailer::Preview
  # "Esqueci minha senha" de quem já entrou alguma vez.
  def reset_password_instructions
    user = User.first.tap { |u| u.sign_in_count = 12 }
    Devise::Mailer.reset_password_instructions(user, "token-de-exemplo")
  end

  # Convite: usuário criado pelo administrador, que ainda não entrou.
  def new_user_invitation
    user = User.new(name: "Ana Souza", email: "ana.souza@devbatista.com", role: Role.find_by(key: "comercial"))
    Devise::Mailer.reset_password_instructions(user, "token-de-exemplo")
  end
end
