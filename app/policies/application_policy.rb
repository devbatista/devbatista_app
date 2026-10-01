# Autorização pela matriz de permissões do perfil (Role).
# Cada policy declara a área do sistema que protege:
#
#   class CompanyPolicy < ApplicationPolicy
#     area "clientes"
#   end
#
# Leitura: index? e show?. Escrita (edit, own ou full): create? e update?.
# No nível "own", o usuário só altera registros em que record.user == user.
# Exclusão exige "full".
class ApplicationPolicy
  attr_reader :user, :record

  class << self
    def area(name = nil)
      name ? @area = name.to_s : @area || superclass_area
    end

    private

    def superclass_area
      superclass.respond_to?(:area) ? superclass.area : nil
    end
  end

  def initialize(user, record)
    @user = user
    @record = record
  end

  def index?
    user.can_read?(area)
  end

  def show?
    index?
  end

  def create?
    user.can_write?(area)
  end

  def new?
    create?
  end

  def update?
    return false unless user.can_write?(area)
    return owns_record? if user.own_only?(area)

    true
  end

  def edit?
    update?
  end

  def destroy?
    user.can_manage?(area)
  end

  private

  def area
    self.class.area || raise(NotImplementedError, "#{self.class} precisa declarar `area`")
  end

  def owns_record?
    record.respond_to?(:user_id) && record.user_id == user.id
  end

  class Scope
    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def resolve
      area = "#{@scope.name}Policy".safe_constantize&.area
      return @scope.none unless area && @user.can_read?(area)
      return @scope.where(user_id: @user.id) if @user.own_only?(area) && @scope.column_names.include?("user_id")

      @scope.all
    end

    private

    attr_reader :user, :scope
  end
end
