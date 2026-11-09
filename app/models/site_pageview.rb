# Página vista numa visita ao site. `client_id` é o id gerado no navegador, que liga o evento de
# saída (leave) à página e torna o envio idempotente. `duration_seconds` é o tempo com a página
# visível, quando o leave chega.
class SitePageview < ApplicationRecord
  # Teto do tempo numa página: uma aba esquecida aberta não distorce a média.
  MAX_DURATION = 30.minutes.to_i

  belongs_to :site_visit

  validates :client_id, :path, :occurred_at, presence: true
end
