# As URLs passaram a ser agrupadas como o menu (/contracts/104 → /customers/contracts/104).
# As notificações guardam o caminho como texto; esta migration acrescenta o grupo às que já existem.
class NamespaceNotificationPaths < ActiveRecord::Migration[8.1]
  GROUPS = {
    "commercial" => %w[leads opportunities proposals pipeline],
    "customers" => %w[companies contacts contracts customer-services],
    "operations" => %w[projects tasks tickets time-entries],
    "finance" => %w[revenues expenses receivables payables recurrences recurring-expenses invoices],
    "technology" => %w[apps servers domains databases integrations external-services],
    "products" => %w[subscriptions],
    "management" => %w[suppliers documents reports indicators profitability]
  }.freeze

  def up
    each_resource { |group, resource| rewrite("/#{resource}", "/#{group}/#{resource}") }
  end

  def down
    each_resource { |group, resource| rewrite("/#{group}/#{resource}", "/#{resource}") }
  end

  private

  def each_resource(&)
    GROUPS.each { |group, resources| resources.each { |resource| yield group, resource } }
  end

  # Só troca o segmento inteiro: "/tasks" não pega "/tasks-algo".
  def rewrite(old, new)
    execute <<~SQL
      UPDATE notifications
      SET path = #{quote(new)} || substr(path, #{old.length + 1})
      WHERE path = #{quote(old)} OR path LIKE #{quote("#{old}/%")} OR path LIKE #{quote("#{old}?%")}
    SQL
  end

  def quote(value)
    connection.quote(value)
  end
end
