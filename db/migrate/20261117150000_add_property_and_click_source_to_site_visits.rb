# Visitas do site (docs/specs/visitas-do-site, v1.1): de qual propriedade é a visita (o site ou as
# prévias de clientes em previews.devbatista.com) e de qual plataforma veio o clique, pelo ID de
# clique da URL (gclid, fbclid…). Só a plataforma: o valor do ID identificaria a pessoa.
class AddPropertyAndClickSourceToSiteVisits < ActiveRecord::Migration[8.1]
  def change
    add_column :site_visits, :property, :string, null: false, default: "site"
    add_column :site_visits, :click_source, :string
    add_index :site_visits, %i[property started_at]
  end
end
