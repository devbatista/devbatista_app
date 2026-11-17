# Visita de uma pessoa ao devbatista.com (docs/specs/visitas-do-site): as páginas vistas pelo mesmo
# visitante com no máximo 30 min entre uma e outra. Criada e atualizada só pelo SiteVisits::Tracker.
# O visitante é um hash do sal do dia, do IP e do user agent: muda à meia-noite e não guarda o IP.
# `property` separa o site das prévias de clientes (previews.devbatista.com), que não entram nos
# números do site.
class SiteVisit < ApplicationRecord
  include LabeledEnums

  # Sem página nova nesse intervalo, a próxima abre outra visita.
  WINDOW = 30.minutes

  labeled_enum :channel, ai_assistant: "Assistentes de IA", email: "E-mail", campaign: "Campanha", search: "Busca",
                         social: "Redes sociais", referral: "Outros sites", direct: "Direto"
  labeled_enum :device_type, desktop: "Computador", mobile: "Celular", tablet: "Tablet"
  labeled_enum :property, { site: "Site", previews: "Prévias" }, prefix: true
  # A plataforma do ID de clique da URL (gclid, fbclid…), nunca o valor do ID.
  labeled_enum :click_source, { google_ads: "Google Ads", microsoft_ads: "Microsoft Ads", meta: "Meta (Facebook e Instagram)",
                                tiktok: "TikTok", linkedin: "LinkedIn", x: "X (Twitter)" }, prefix: true, validate: { allow_nil: true }

  has_many :pageviews, class_name: "SitePageview", dependent: :delete_all

  validates :visitor_hash, :started_at, :last_seen_at, :entry_path, :exit_path, presence: true

  # A visita ainda aberta desse visitante na mesma propriedade, se houver: ir do site para uma prévia
  # abre outra visita.
  def self.open_for(visitor_hash, at, property: "site")
    where(visitor_hash: visitor_hash, property: property).where(last_seen_at: (at - WINDOW)..).order(last_seen_at: :desc).first
  end
end
