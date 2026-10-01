require "rails_helper"

RSpec.describe "Autenticação" do
  let!(:user) { create(:user, email: "ana@devbatista.com", password: "senha-segura-123") }

  it "manda para o login quem não entrou" do
    get root_path
    expect(response).to redirect_to(new_user_session_path)
  end

  it "entra com e-mail e senha e registra o login na auditoria" do
    expect {
      post user_session_path, params: { user: { email: "ana@devbatista.com", password: "senha-segura-123" } }
    }.to change { AuditLog.where(action: "login", user: user).count }.by(1)
    expect(response).to redirect_to(root_path)
  end

  it "registra a falha de login" do
    expect {
      post user_session_path, params: { user: { email: "ana@devbatista.com", password: "errada" } }
    }.to change { AuditLog.where(action: "login_failed").count }.by(1)
  end

  it "bloqueia a conta após 5 tentativas inválidas" do
    5.times { post user_session_path, params: { user: { email: "ana@devbatista.com", password: "errada" } } }
    expect(user.reload.access_locked?).to be(true)
  end

  it "não deixa entrar usuário desativado" do
    user.update!(active: false)
    post user_session_path, params: { user: { email: "ana@devbatista.com", password: "senha-segura-123" } }
    follow_redirect!
    expect(response.body).to include("Seu usuário foi desativado")
  end

  it "registra o logout" do
    sign_in user
    expect { delete destroy_user_session_path }.to change { AuditLog.where(action: "logout").count }.by(1)
  end
end
