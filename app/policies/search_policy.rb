# A busca está disponível para todos; os resultados respeitam o perfil (Search::Query).
class SearchPolicy < ApplicationPolicy
  def index? = true
end
