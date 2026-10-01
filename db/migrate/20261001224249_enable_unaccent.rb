# Busca sem diferenciar acentos ("joao" encontra "João").
class EnableUnaccent < ActiveRecord::Migration[8.1]
  def change
    enable_extension "unaccent"
  end
end
