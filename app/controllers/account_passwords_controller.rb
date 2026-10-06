# Cada usuário troca a própria senha, confirmando a senha atual.
class AccountPasswordsController < ApplicationController
  before_action :set_user

  def edit; end

  def update
    # update_with_password ignora a nova senha em branco e "salva" sem trocar nada.
    if password_params[:password].blank?
      @user.errors.add(:password, :blank)
    elsif @user.update_with_password(password_params)
      AuditLog.record!(action: "password_change", area: "acesso", record: @user)
      # A troca de senha invalida a sessão atual; mantém o usuário logado.
      bypass_sign_in(@user)
      return redirect_to root_path, notice: "Senha alterada."
    end

    render :edit, status: :unprocessable_entity
  end

  private

  def set_user
    @user = authorize current_user, :change_password?
  end

  def password_params
    params.expect(user: %i[current_password password password_confirmation])
  end
end
