# Alerta na central de notificações de um usuário (RF 5).
class Notification < ApplicationRecord
  include LabeledEnums

  # Tipos de alerta, com o perfil que recebe (cap. 36). Cada fase acrescenta os seus.
  KINDS = {
    "contract_expiring" => { label: "Contratos vencendo", roles: %w[admin comercial], area: "contratos",
                             trigger: -> { "#{Setting[:contract_alert_days].to_sentence} dias antes do término" } },
    "proposal_expiring" => { label: "Propostas expirando", roles: :owner, area: "comercial",
                             trigger: -> { "#{Setting[:proposal_alert_days]} dias antes do fim da validade" } },
    "task_late" => { label: "Tarefas atrasadas", roles: :owner, area: "projetos",
                     trigger: -> { "Prazo ultrapassado e tarefa não concluída" } },
    "project_late" => { label: "Projetos atrasados", roles: :owner, area: "projetos", audience: "responsável e administradores",
                        trigger: -> { "Previsão ultrapassada e projeto não concluído" } },
    "ticket_critical" => { label: "Chamados críticos", roles: %w[admin suporte desenvolvedor], area: "suporte",
                           trigger: -> { "Abertura ou mudança para prioridade Crítica (na hora)" } }
  }.freeze

  labeled_enum :level, { info: "Informativo", warn: "Atenção", crit: "Crítico" }, prefix: true

  belongs_to :user
  belongs_to :notifiable, polymorphic: true, optional: true

  validates :kind, inclusion: { in: KINDS.keys }
  validates :title, :area, presence: true

  scope :unread, -> { where(read_at: nil) }
  scope :recent, -> { order(created_at: :desc, id: :desc) }

  # Cria o alerta para cada usuário ativo dos perfis do tipo. Com dedup_key, não
  # repete o mesmo alerta se a rotina rodar duas vezes.
  # Alertas com roles: :owner vão só para o responsável do registro (users:).
  def self.deliver!(kind:, title:, path: nil, notifiable: nil, level: "info", dedup_key: nil, users: nil)
    config = KINDS.fetch(kind)
    users ||= User.active.joins(:role).where(roles: { key: config[:roles] })
    users = Array(users).select(&:active?)
    users.filter_map do |user|
      next if dedup_key && exists?(user: user, dedup_key: dedup_key)

      notification = create!(user: user, kind: kind, title: title, path: path, notifiable: notifiable,
                             level: level, area: config[:area], dedup_key: dedup_key)
      NotificationMailer.alert(notification).deliver_later if user.email_for?(kind) && Setting[:email_enabled]
      notification
    end
  end

  def read?
    read_at.present?
  end

  def kind_label
    KINDS.dig(kind, :label)
  end

  # Quem recebe o alerta, em texto (para a tela de preferências).
  def self.receives?(kind, user)
    roles = KINDS.dig(kind, :roles)
    roles == :owner ? user.can_read?(KINDS.dig(kind, :area)) : roles.include?(user.role.key)
  end
end
