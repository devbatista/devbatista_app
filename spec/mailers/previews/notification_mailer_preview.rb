# Pré-visualização em /rails/mailers (desenvolvimento).
class NotificationMailerPreview < ActionMailer::Preview
  def alert_critical
    NotificationMailer.alert(notification(kind: "receivable_overdue", level: "crit",
                                          title: "Título de R$ 4.800,00 da Acme vencido desde 03/10"))
  end

  def alert_warning
    NotificationMailer.alert(notification(kind: "contract_expiring", level: "warn",
                                          title: "Contrato #104 da Acme vence em 30 dias"))
  end

  def alert_info
    NotificationMailer.alert(notification(kind: "task_late", level: "info", title: "Tarefa “Ajustar checkout” passou do prazo"))
  end

  def site_lead_diagnosis
    lead = Lead.new(id: SecureRandom.uuid, name: "Ana Souza", company_name: "Clínica Sorriso", email: "ana@clinica.com.br",
                    whatsapp: "(11) 98765-4321", origin: "diagnosis")
    NotificationMailer.with(site_lead: {
      "origin" => "Diagnóstico Tecnológico", "tier" => "Quente",
      "summary" => "Diagnóstico pelo site: Alto potencial de otimização (22 pontos) · potencial quente · Automatização de tarefas",
      "details" => "Diagnóstico Tecnológico — 26/11/2026 10:00\nPrincipal desafio: Automatização de tarefas\n\nSistemas: Planilhas\nEquipe: 6 a 20"
    }).alert(notification(kind: "site_lead", level: "warn", notifiable: lead, path: "/commercial/leads/#{lead.id}",
                          title: "Novo lead do site: Clínica Sorriso · Ana Souza · potencial quente"))
  end

  def site_lead_contact
    lead = Lead.new(id: SecureRandom.uuid, name: "Maria Souza", company_name: "Escritório X", whatsapp: "(11) 99999-0000", origin: "site")
    NotificationMailer.with(site_lead: {
      "origin" => "Formulário de contato", "need" => "Atendimento com IA no WhatsApp", "segment" => "Contabilidade",
      "summary" => "Contato pelo site: Atendimento com IA no WhatsApp · Contabilidade",
      "details" => "Segmento: Contabilidade\nMensagens por mês no WhatsApp: 300 a 1.000\nCaso: muitas dúvidas repetidas\nConsentimento de contato: sim"
    }).alert(notification(kind: "site_lead", level: "warn", notifiable: lead, path: "/commercial/leads/#{lead.id}",
                          title: "Novo contato do site: Escritório X · Maria Souza"))
  end

  private

  def notification(**attributes)
    Notification.new(user: User.first, path: "/", **attributes)
  end
end
