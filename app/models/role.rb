# Perfil de acesso. Cada usuário tem exatamente um.
# A matriz de permissões guarda, para cada área do sistema, um nível:
#   none (sem acesso), read (leitura), own (só os próprios registros),
#   edit (cria e edita) e full (cria, edita, exclui e configura).
class Role < ApplicationRecord
  LEVELS = %w[none read own edit full].freeze

  AREAS = {
    "dashboard" => "Dashboard",
    "comercial" => "Comercial",
    "clientes" => "Clientes e contatos",
    "contratos" => "Contratos e serviços contratados",
    "projetos" => "Projetos e tarefas",
    "horas" => "Horas trabalhadas",
    "suporte" => "Suporte",
    "financeiro" => "Financeiro",
    "tecnologia" => "Tecnologia",
    "produtos" => "Produtos",
    "fornecedores" => "Fornecedores",
    "documentos" => "Documentos",
    "relatorios" => "Relatórios e indicadores",
    "administracao" => "Administração"
  }.freeze

  # Matriz inicial (docs/specs/admin-devbatista-mvp/02-personas-e-perfis-de-acesso.md).
  DEFAULTS = {
    "admin" => { name: "Administrador", permissions: AREAS.keys.index_with("full") },
    "comercial" => {
      name: "Comercial",
      permissions: {
        "dashboard" => "read", "comercial" => "edit", "clientes" => "edit", "contratos" => "edit",
        "projetos" => "read", "suporte" => "read", "produtos" => "read", "documentos" => "edit",
        "relatorios" => "read"
      }
    },
    "financeiro" => {
      name: "Financeiro",
      permissions: {
        "dashboard" => "read", "comercial" => "read", "clientes" => "read", "contratos" => "edit",
        "horas" => "read", "financeiro" => "edit", "tecnologia" => "read", "produtos" => "read",
        "fornecedores" => "edit", "documentos" => "edit", "relatorios" => "read"
      }
    },
    "suporte" => {
      name: "Suporte",
      permissions: {
        "dashboard" => "read", "clientes" => "read", "contratos" => "read", "projetos" => "read",
        "horas" => "own", "suporte" => "edit", "tecnologia" => "read", "documentos" => "read",
        "relatorios" => "read"
      }
    },
    "desenvolvedor" => {
      name: "Desenvolvedor",
      permissions: {
        "dashboard" => "read", "clientes" => "read", "projetos" => "edit", "horas" => "own",
        "suporte" => "edit", "tecnologia" => "edit", "produtos" => "read", "fornecedores" => "read",
        "documentos" => "read", "relatorios" => "read"
      }
    }
  }.freeze

  has_many :users, dependent: :restrict_with_error

  validates :name, presence: true
  validates :key, presence: true, uniqueness: true
  validate :permissions_are_valid

  def self.seed_defaults!
    DEFAULTS.each do |key, attrs|
      find_or_create_by!(key: key) do |role|
        role.name = attrs[:name]
        role.permissions = attrs[:permissions]
      end
    end
  end

  def admin?
    key == "admin"
  end

  # Cartões financeiros do dashboard e dos relatórios só aparecem para estes perfis.
  def sees_financials?
    admin? || key == "financeiro"
  end

  def level_for(area)
    return "full" if admin?

    permissions.fetch(area.to_s, "none")
  end

  def can_read?(area)
    level_for(area) != "none"
  end

  def can_write?(area)
    %w[own edit full].include?(level_for(area))
  end

  def own_only?(area)
    level_for(area) == "own"
  end

  def can_manage?(area)
    level_for(area) == "full"
  end

  private

  def permissions_are_valid
    unknown = permissions.keys - AREAS.keys
    errors.add(:permissions, "têm áreas desconhecidas: #{unknown.join(', ')}") if unknown.any?
    invalid = permissions.values - LEVELS
    errors.add(:permissions, "têm níveis inválidos: #{invalid.uniq.join(', ')}") if invalid.any?
  end
end
