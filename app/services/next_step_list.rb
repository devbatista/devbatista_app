# Lista Comercial → Próximos passos: leads em aberto (Novo, Contato Realizado, Qualificado) e
# oportunidades em aberto (sem Fechado e Perdido) numa lista só, pela data e hora do próximo passo,
# do mais antigo para o mais novo. Os sem data vão no fim ("Sem próximo passo"), para nada se perder.
#
# Usada pela tela (Commercial::NextStepsController) e pela tool proximos_passos do MCP. Recebe os
# escopos já filtrados pela permissão (policy_scope).
class NextStepList
  GROUPS = {
    "atrasados" => "Atrasados", "hoje" => "Hoje", "amanha" => "Amanhã",
    "proximos_7_dias" => "Próximos 7 dias", "depois" => "Depois", "sem_data" => "Sem próximo passo"
  }.freeze
  KINDS = %w[lead oportunidade].freeze

  # Uma linha da lista, igual para lead e oportunidade.
  Item = Data.define(:record) do
    def lead? = record.is_a?(Lead)
    def kind = lead? ? "lead" : "oportunidade"
    def kind_label = lead? ? "Lead" : "Oportunidade"
    def at = record.next_step_on
    def action = record.next_step
    def name = lead? ? record.name : record.title
    def company = lead? ? (record.company&.trade_name || record.company_name.presence) : record.company.trade_name
    def status = lead? ? record.status : record.stage
    def status_label = lead? ? record.status_label : record.stage_label
    def overdue?(now = Time.current) = record.next_step_overdue?(now)

    # Oportunidade não tem WhatsApp próprio: vem do lead de origem ou do contato principal da empresa.
    def whatsapp
      return record.whatsapp.presence if lead?

      record.lead&.whatsapp.presence || record.company.primary_contact&.whatsapp.presence
    end
  end

  attr_reader :now

  # kind: "lead" ou "oportunidade" (nil = os dois). origin: só leads têm origem; a oportunidade usa a
  # do lead de onde veio. from/to: limites da data do próximo passo. include_overdue: os atrasados
  # entram mesmo antes de from. include_undated: os sem data.
  def initialize(leads:, opportunities:, kind: nil, origin: nil, user_id: nil, from: nil, to: nil,
                 include_overdue: true, include_undated: true, now: Time.current)
    @leads = leads
    @opportunities = opportunities
    @kind = kind.presence
    @origin = origin.presence
    @user_id = user_id.presence
    @from = from
    @to = to
    @include_overdue = include_overdue
    @include_undated = include_undated
    @now = now
  end

  # Última interação de cada registro, numa consulta: { [subject_type, subject_id] => Interaction }.
  def self.last_interactions(records)
    return {} if records.empty?

    Interaction.where(subject: records)
               .select("DISTINCT ON (interactions.subject_type, interactions.subject_id) interactions.*")
               .order(:subject_type, :subject_id, occurred_on: :desc, created_at: :desc)
               .index_by { |interaction| [ interaction.subject_type, interaction.subject_id ] }
  end

  def items(limit: nil)
    records = scopes.flat_map { |scope| (limit ? scope.limit(limit) : scope).to_a }
    sorted = records.sort_by { |record| [ record.next_step_on ? 0 : 1, record.next_step_on || record.created_at, record.created_at ] }
                    .map { |record| Item.new(record) }
    limit ? sorted.first(limit) : sorted
  end

  def total
    scopes.sum { |scope| scope.unscope(:order).count }
  end

  # Itens por grupo, na ordem de GROUPS (todos os grupos, mesmo vazios).
  def groups(items = self.items)
    found = items.group_by { |item| group_of(item.at) }
    GROUPS.keys.index_with { |key| found.fetch(key, []) }
  end

  def group_of(time)
    return "sem_data" if time.nil?
    return "atrasados" if time < now

    today = now.to_date
    date = time.to_date
    return "hoje" if date == today
    return "amanha" if date == today + 1

    date <= today + 7 ? "proximos_7_dias" : "depois"
  end

  private

  attr_reader :kind, :origin, :user_id, :from, :to, :include_overdue, :include_undated

  def scopes
    [ (lead_scope unless kind == "oportunidade"), (opportunity_scope unless kind == "lead") ].compact
  end

  def lead_scope
    scope = @leads.open.includes(:company, :user)
    scope = scope.where(origin: origin) if origin
    scope = scope.where(user_id: user_id) if user_id
    by_date(filter_dates(scope), "leads")
  end

  def opportunity_scope
    scope = @opportunities.open.includes(:user, :lead, company: :primary_contact)
    scope = scope.joins(:lead).where(leads: { origin: origin }) if origin
    scope = scope.where(user_id: user_id) if user_id
    by_date(filter_dates(scope), "opportunities")
  end

  def filter_dates(scope)
    return scope if from.nil? && to.nil? && include_overdue && include_undated

    dated = scope.with_next_step_date
    dated = dated.where(next_step_on: from..) if from
    dated = dated.where(next_step_on: ..to) if to
    dated = include_overdue ? dated.or(scope.next_step_overdue(now)) : dated.where(next_step_on: now..)
    include_undated ? dated.or(scope.where(next_step_on: nil)) : dated
  end

  def by_date(scope, table)
    scope.order(Arel.sql("#{table}.next_step_on IS NULL, #{table}.next_step_on, #{table}.created_at"))
  end
end
