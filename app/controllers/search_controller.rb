# Busca global (RF 4): página de resultados e JSON para a paleta ⌘K.
class SearchController < ApplicationController
  def index
    authorize :search, :index?
    @query = params[:q].to_s.strip
    @groups = Search::Query.new(current_user, @query).groups
    respond_to do |format|
      format.html
      format.json { render json: @groups.map { |g| { label: g.label, items: g.items.map { |i| i.to_h.merge(path: i.path) } } } }
    end
  end
end
