class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # Chaves são UUID v4 (aleatórias): first/last sem order explícito seguem a criação,
  # com desempate pela chave.
  self.implicit_order_column = "created_at"
end
