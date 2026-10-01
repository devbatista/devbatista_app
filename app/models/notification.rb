# Alerta na central de notificações de um usuário (RF 5).
class Notification < ApplicationRecord
  include LabeledEnums

  # Tipos de alerta, com o perfil que recebe (cap. 36). Cada fase acrescenta os seus.
  KINDS = {
    "contract_expiring" => { label: "Contratos vencendo", roles: %w[admin comercial], area: "contratos" }
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
  def self.deliver!(kind:, title:, path: nil, notifiable: nil, level: "info", dedup_key: nil)
    config = KINDS.fetch(kind)
    users = User.active.joins(:role).where(roles: { key: config[:roles] })
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
end
