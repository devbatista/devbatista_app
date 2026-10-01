require "rails_helper"

RSpec.describe "Administração → Usuários" do
  let(:admin) { create(:user, :admin) }

  it "lista os usuários para o administrador" do
    sign_in admin
    get admin_users_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(admin.name)
  end

  it "responde 403 para perfil sem acesso à Administração" do
    sign_in create(:user, :comercial)
    get admin_users_path
    expect(response).to have_http_status(:forbidden)
  end

  it "cria o usuário e envia o link para definir a senha" do
    sign_in admin
    expect {
      post admin_users_path, params: { user: { name: "Nova Pessoa", email: "nova@devbatista.com", role_id: create(:role, :suporte).id } }
    }.to change(User, :count).by(1).and have_enqueued_mail(Devise::Mailer, :reset_password_instructions)
    expect(response).to redirect_to(admin_users_path)
  end

  it "desativa sem excluir" do
    sign_in admin
    other = create(:user, :suporte)
    patch toggle_active_admin_user_path(other)
    expect(other.reload.active?).to be(false)
  end

  it "não deixa o administrador desativar a si mesmo" do
    sign_in admin
    patch toggle_active_admin_user_path(admin)
    expect(response).to have_http_status(:forbidden)
  end
end
