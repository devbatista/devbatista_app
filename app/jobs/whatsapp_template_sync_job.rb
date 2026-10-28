# Sincronização dos templates de uma conta com a Meta (docs/specs/whatsapp, Fase 5), pelo botão
# da tela e pela rotina diária (DailyAlertsJob). Lê todos os templates da WABA (Client#templates,
# com paginação) e grava pelo meta_template_id ou, se o template do Admin ainda não tem ID, por
# nome e idioma. Os criados direto no Gerenciador do WhatsApp entram assim na lista.
# O template que sumiu da Meta fica como excluído, sem apagar: as mensagens antigas apontam para ele.
class WhatsappTemplateSyncJob < ApplicationJob
  queue_as :default
  discard_on ActiveJob::DeserializationError
  retry_on Whatsapp::Error, wait: :polynomially_longer, attempts: 5 do |job, error|
    job.arguments.first.update!(templates_sync_error: error.user_message.to_s.truncate(255))
  end

  def self.enqueue_all
    WhatsappAccount.where(status: WhatsappAccount::ACTIVE_STATUSES).find_each { |account| perform_later(account) }
  end

  def perform(account)
    return unless account.templates_syncable?

    now = Time.current
    remote = Whatsapp::Client.new(account).templates
    # Primeiro os que sumiram: libera o nome e o idioma para um template novo com o mesmo nome.
    account.templates.current.where.not(meta_template_id: [ nil, *remote.map { |data| data["id"].to_s } ])
           .find_each { |template| template.update!(status: "deleted", last_synced_at: now) }
    remote.each { |data| upsert(account, data, now) }
    account.update!(templates_synced_at: now, templates_sync_error: nil)
    Rails.logger.info("[Whatsapp] templates sincronizados: phone_number_id=#{account.phone_number_id}, #{remote.size} na Meta")
  rescue Whatsapp::Error => e
    raise if e.transient?

    account.update!(templates_sync_error: e.user_message.to_s.truncate(255))
  end

  private

  def upsert(account, data, now)
    template = account.templates.find_by(meta_template_id: data["id"].to_s) ||
               account.templates.current.where(meta_template_id: nil).find_by(name: data["name"], language: data["language"]) ||
               account.templates.new
    # Sem motivo na Meta (NONE), o motivo antigo sai: o template rejeitado pode ter sido aprovado.
    attributes = { rejection_reason: nil }.merge(WhatsappTemplate.attributes_from_meta(data, current: template))
    template.update!(attributes.merge(last_synced_at: now))
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
    Rails.logger.warn("[Whatsapp] template #{data["name"]} (#{data["id"]}) não sincronizado: #{e.class}")
  end
end
