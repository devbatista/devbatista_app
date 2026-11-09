# Visitas do site e acessos de IA (docs/specs/visitas-do-site): só leitura, na tela e no MCP.
# Ninguém cria nem altera visitas pelo sistema; quem grava é o webhook do site.
class SiteVisitPolicy < ApplicationPolicy
  area "marketing"
end
