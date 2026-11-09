# Página do site buscada por um robô ou agente de IA (docs/specs/visitas-do-site, Acessos de IA).
# Não é visita de pessoa e não entra em nenhum indicador de visitas. Guarda o agente como estava
# no catálogo (config/ai_agents.yml) na hora do acesso, para o histórico não mudar com o catálogo.
class AiHit < ApplicationRecord
  include LabeledEnums

  labeled_enum :kind, training: "Treino", search: "Busca com IA", user: "A pedido de alguém", agent: "Navegação autônoma"
  # O falso não entra nos totais: user agent do catálogo vindo de fora das faixas de IP oficiais.
  labeled_enum :verification, signed: "Assinado", ip_verified: "IP confirmado", declared: "Declarado", spoofed: "Falso"

  validates :agent, :agent_name, :company, :path, :occurred_at, presence: true

  scope :genuine, -> { where.not(verification: "spoofed") }
  # Barrados pelo .htaccess do site (403): a tentativa conta, mas a página não foi entregue.
  scope :blocked, -> { where(blocked: true) }
  scope :served, -> { where(blocked: false) }
end
