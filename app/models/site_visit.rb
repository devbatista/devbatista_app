# Visita de uma pessoa ao devbatista.com (docs/specs/visitas-do-site): as páginas vistas pelo mesmo
# visitante com no máximo 30 min entre uma e outra. Criada e atualizada só pelo SiteVisitTracker.
# O visitante é um hash do sal do dia, do IP e do user agent: muda à meia-noite e não guarda o IP.
class SiteVisit < ApplicationRecord
  include LabeledEnums

  # Sem página nova nesse intervalo, a próxima abre outra visita.
  WINDOW = 30.minutes

  labeled_enum :channel, ai_assistant: "Assistentes de IA", email: "E-mail", campaign: "Campanha", search: "Busca",
                         social: "Redes sociais", referral: "Outros sites", direct: "Direto"
  labeled_enum :device_type, desktop: "Computador", mobile: "Celular", tablet: "Tablet"

  has_many :pageviews, class_name: "SitePageview", dependent: :delete_all

  validates :visitor_hash, :started_at, :last_seen_at, :entry_path, :exit_path, presence: true

  # A visita ainda aberta desse visitante, se houver.
  def self.open_for(visitor_hash, at)
    where(visitor_hash: visitor_hash).where(last_seen_at: (at - WINDOW)..).order(last_seen_at: :desc).first
  end
end
