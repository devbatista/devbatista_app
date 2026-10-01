# Paginação e ordenação das listagens (padrão comum a todas as telas).
module Listing
  extend ActiveSupport::Concern

  PER_PAGE = 25

  Pager = Struct.new(:page, :per, :total) do
    def pages = [ (total / per.to_f).ceil, 1 ].max
    def from = total.zero? ? 0 : (page - 1) * per + 1
    def to = [ page * per, total ].min
    def prev? = page > 1
    def next? = page < pages
  end

  private

  def paginate(scope, per: PER_PAGE)
    total = scope.unscope(:order, :select).count
    page = params[:page].to_i.clamp(1, [ (total / per.to_f).ceil, 1 ].max)
    [ scope.offset((page - 1) * per).limit(per), Pager.new(page, per, total) ]
  end

  # sorts: { "nome" => ["Nome (A–Z)", ->(s) { s.order(:name) }], ... }; o primeiro é o padrão.
  def apply_sort(scope, sorts)
    @sorts = sorts
    @sort = sorts.key?(params[:ordem]) ? params[:ordem] : sorts.keys.first
    sorts[@sort].last.call(scope)
  end
end
