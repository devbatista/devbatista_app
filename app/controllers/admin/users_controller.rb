module Admin
  class UsersController < ApplicationController
    before_action :set_user, only: %i[edit update]

    def index
      authorize User
      @users = policy_scope(User).includes(:role).by_name
      @stats = {
        active: User.active.count,
        active_roles: User.active.distinct.count(:role_id),
        today: User.where(current_sign_in_at: Time.current.all_day).count,
        inactive: User.where(active: false).count
      }
    end

    def new
      @user = authorize User.new(active: true)
    end

    def create
      @user = authorize User.new(user_params)
      @user.password = @user.password_confirmation = SecureRandom.base58(24) if @user.password.blank?

      if @user.save
        @user.send_reset_password_instructions
        redirect_to admin_users_path, notice: "Usuário criado. #{@user.first_name} recebeu um e-mail para definir a senha."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @user.update(user_params)
        redirect_to admin_users_path, notice: "Usuário atualizado."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def toggle_active
      @user = authorize User.find(params[:id]), :deactivate?
      @user.update!(active: !@user.active?)
      redirect_to admin_users_path, notice: @user.active? ? "#{@user.name} foi reativado." : "#{@user.name} foi desativado."
    end

    private

    def set_user
      @user = authorize User.find(params[:id])
    end

    def user_params
      params.expect(user: %i[name email role_id hourly_cost])
    end
  end
end
