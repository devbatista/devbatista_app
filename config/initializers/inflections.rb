# Plural em português para o pluralize das telas ("3 contratos", "2 serviços", "1 alerta").
ActiveSupport::Inflector.inflections(:"pt-BR") do |inflect|
  inflect.plural(/$/, "s")
  inflect.plural(/(s|z|r)$/i, '\1es')
  inflect.plural(/al$/i, "ais")
  inflect.plural(/el$/i, "éis")
  inflect.plural(/ol$/i, "óis")
  inflect.plural(/ul$/i, "uis")
  inflect.plural(/il$/i, "is")
  inflect.plural(/m$/i, "ns")
  inflect.plural(/ão$/i, "ões")
end
