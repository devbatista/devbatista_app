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

  describe "troca da própria senha" do
    let(:user) { create(:user, :suporte, email: "ana@devbatista.com", password: "senha-segura-123") }

    def change_password(current:, password:, confirmation: password)
      patch account_password_path, params: { user: { current_password: current, password: password, password_confirmation: confirmation } }
    end

    before { sign_in user }

    it "abre a tela para qualquer perfil" do
      get edit_account_password_path
      expect(response).to have_http_status(:ok)
    end

    it "troca a senha, mantém o usuário logado e registra na auditoria" do
      expect {
        change_password(current: "senha-segura-123", password: "nova-senha-forte-1")
      }.to change { AuditLog.where(action: "password_change", user: user).count }.by(1)

      expect(response).to redirect_to(root_path)
      expect(user.reload.valid_password?("nova-senha-forte-1")).to be(true)
      get root_path
      expect(response).to have_http_status(:ok)
    end

    it "recusa quando a senha atual está errada" do
      change_password(current: "errada", password: "nova-senha-forte-1")
      expect(response).to have_http_status(:unprocessable_entity)
      expect(user.reload.valid_password?("senha-segura-123")).to be(true)
    end

    it "recusa quando a confirmação não confere" do
      change_password(current: "senha-segura-123", password: "nova-senha-forte-1", confirmation: "outra-coisa-1")
      expect(response).to have_http_status(:unprocessable_entity)
      expect(user.reload.valid_password?("senha-segura-123")).to be(true)
    end

    it "recusa nova senha em branco" do
      expect {
        change_password(current: "senha-segura-123", password: "")
      }.not_to change { AuditLog.where(action: "password_change").count }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
