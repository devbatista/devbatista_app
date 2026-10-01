module Admin
  module PermissionsHelper
    LEVEL_LABELS = { "full" => "Total", "edit" => "Edição", "read" => "Leitura", "own" => "Próprio", "none" => "—" }.freeze

    LEVEL_DESCRIPTIONS = {
      "full" => "Cria, edita, exclui e configura.",
      "edit" => "Cria e edita.",
      "read" => "Só consulta.",
      "own" => "Cria e edita só os próprios registros.",
      "none" => "Módulo fora do menu; a rota responde 403."
    }.freeze

    def permission_level_options(selected)
      options_for_select(%w[full edit read own none].map { |level| [ LEVEL_LABELS[level], level ] }, selected)
    end
  end
end
