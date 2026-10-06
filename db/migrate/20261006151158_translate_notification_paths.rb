# As URLs passaram para o inglês (/contratos/104 → /contracts/104). As notificações guardam
# o caminho como texto; esta migration troca o primeiro segmento das que já existem.
class TranslateNotificationPaths < ActiveRecord::Migration[8.1]
  PREFIXES = {
    "empresas" => "companies", "contatos" => "contacts", "contratos" => "contracts",
    "servicos-contratados" => "customer-services", "documentos" => "documents",
    "oportunidades" => "opportunities", "propostas" => "proposals",
    "projetos" => "projects", "tarefas" => "tasks", "horas" => "time-entries", "chamados" => "tickets",
    "financeiro" => "finance", "receitas" => "revenues", "contas-a-receber" => "receivables",
    "despesas" => "expenses", "contas-a-pagar" => "payables", "recorrencias" => "recurrences",
    "despesas-recorrentes" => "recurring-expenses", "notas-fiscais" => "invoices", "fornecedores" => "suppliers",
    "aplicacoes" => "apps", "servidores" => "servers", "dominios" => "domains", "bancos-de-dados" => "databases",
    "integracoes" => "integrations", "servicos-externos" => "external-services",
    "produtos" => "products", "assinaturas" => "subscriptions",
    "indicadores" => "indicators", "rentabilidade" => "profitability", "relatorios" => "reports",
    "notificacoes" => "notifications", "busca" => "search", "administracao" => "admin"
  }.freeze

  def up
    PREFIXES.each { |from, to| rewrite(from, to) }
  end

  def down
    PREFIXES.each { |from, to| rewrite(to, from) }
  end

  private

  # Só troca o segmento inteiro: "/despesas" não pega "/despesas-recorrentes".
  def rewrite(from, to)
    old = "/#{from}"
    execute <<~SQL
      UPDATE notifications
      SET path = #{quote("/#{to}")} || substr(path, #{old.length + 1})
      WHERE path = #{quote(old)} OR path LIKE #{quote("#{old}/%")} OR path LIKE #{quote("#{old}?%")}
    SQL
  end

  def quote(value)
    connection.quote(value)
  end
end
