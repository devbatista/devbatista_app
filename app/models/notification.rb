# Alerta na central de notificações de um usuário (RF 5). O sino do topo acompanha em tempo real
# (stream [usuário, :notifications], NotificationsChannel): criar, atualizar ou ler redesenha o
# contador e a lista.
class Notification < ApplicationRecord
  include LabeledEnums

  # Tipos de alerta, com o perfil que recebe (cap. 36). Cada fase acrescenta os seus.
  # area_readers: recebe também quem pode ver a área. email_default: false deixa o e-mail desligado
  # até a pessoa ligar nas preferências.
  KINDS = {
    "contract_expiring" => { label: "Contratos vencendo", roles: %w[admin comercial], area: "contratos",
                             trigger: -> { "#{Setting[:contract_alert_days].to_sentence} dias antes do término" } },
    "proposal_expiring" => { label: "Propostas expirando", roles: :owner, area: "comercial",
                             trigger: -> { "#{Setting[:proposal_alert_days]} dias antes do fim da validade" } },
    "task_late" => { label: "Tarefas atrasadas", roles: :owner, area: "projetos",
                     trigger: -> { "Prazo ultrapassado e tarefa não concluída" } },
    "project_late" => { label: "Projetos atrasados", roles: :owner, area: "projetos", audience: "responsável e administradores",
                        trigger: -> { "Previsão ultrapassada e projeto não concluído" } },
    "receivable_overdue" => { label: "Pagamentos vencidos", roles: %w[admin financeiro], area: "financeiro",
                              trigger: -> { "Dia seguinte ao vencimento de um título a receber sem pagamento" } },
    "payable_overdue" => { label: "Contas a pagar vencidas", roles: %w[admin financeiro], area: "financeiro",
                           trigger: -> { "Dia seguinte ao vencimento de uma conta a pagar sem pagamento" } },
    "domain_expiring" => { label: "Domínios vencendo", roles: %w[admin desenvolvedor], area: "tecnologia",
                           trigger: -> { "#{Setting[:domain_alert_days].to_sentence} dias antes do vencimento" } },
    "ticket_critical" => { label: "Chamados críticos", roles: %w[admin suporte desenvolvedor], area: "suporte",
                           trigger: -> { "Abertura ou mudança para prioridade Crítica (na hora)" } },
    "whatsapp_message" => { label: "Mensagens do WhatsApp", roles: %w[admin], area: "whatsapp", area_readers: true, email_default: false,
                            audience: "quem vê as conversas", trigger: -> { "Mensagem recebida numa conversa (um aviso por conversa)" } },
    "whatsapp_token_expiring" => { label: "Acesso do WhatsApp vencendo", roles: %w[admin], area: "whatsapp",
                                   trigger: -> { "7 dias antes e no dia do vencimento do token" } }
  }.freeze

  labeled_enum :level, { info: "Informativo", warn: "Atenção", crit: "Crítico" }, prefix: true

  belongs_to :user
  belongs_to :notifiable, polymorphic: true, optional: true

  validates :kind, inclusion: { in: KINDS.keys }
  validates :title, :area, presence: true

  scope :unread, -> { where(read_at: nil) }
  scope :recent, -> { order(created_at: :desc, id: :desc) }

  after_commit :refresh_bell

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
      notification.email_later
      notification
    end
  end

  # Redesenha o sino do usuário (contador e lista). Para as marcações em lote (update_all), que não
  # passam pelos callbacks.
  def self.refresh_bell(user)
    stream = [ user, :notifications ]
    Turbo::StreamsChannel.broadcast_replace_later_to(stream, target: "notifications_bell_button", partial: "notifications/bell_button", locals: { user: user })
    Turbo::StreamsChannel.broadcast_replace_later_to(stream, target: "notifications_bell_list", partial: "notifications/bell_list", locals: { user: user })
  end

  def email_later
    NotificationMailer.alert(self).deliver_later if user.email_for?(kind) && Setting[:email_enabled]
  end

  def read?
    read_at.present?
  end

  def kind_label
    KINDS.dig(kind, :label)
  end

  # Quem recebe o alerta, em texto (para a tela de preferências).
  def self.receives?(kind, user)
    config = KINDS.fetch(kind)
    return user.can_read?(config[:area]) if config[:roles] == :owner || (config[:area_readers] && user.can_read?(config[:area]))

    config[:roles].include?(user.role.key)
  end

  private

  def refresh_bell
    self.class.refresh_bell(user) if user
  end
end
