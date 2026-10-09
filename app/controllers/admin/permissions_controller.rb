module Admin
  # Matriz de permissões: uma linha por área, uma coluna por perfil.
  class PermissionsController < ApplicationController
    def show
      authorize Role, :index?
      @roles = Role.ordered
    end

    def update
      authorize Role, :index?
      roles = Role.where.not(key: "admin").ordered

      Role.transaction do
        roles.each do |role|
          authorize role, :update?
          role.update!(permissions: permissions_for(role))
        end
      end
      redirect_to admin_permissions_path, notice: "Permissões salvas."
    rescue ActiveRecord::RecordInvalid => e
      @roles = Role.ordered
      flash.now[:alert] = e.record.errors.full_messages.to_sentence
      render :show, status: :unprocessable_entity
    end

    private

    def permissions_for(role)
      levels = params.dig(:permissions, role.key)&.permit(*Role::AREAS.keys).to_h || {}
      levels.reject { |_area, level| level == "none" }
    end
  end
end
