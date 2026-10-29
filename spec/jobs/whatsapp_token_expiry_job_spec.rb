require "rails_helper"

RSpec.describe WhatsappTokenExpiryJob do
  around { |example| travel_to(Time.zone.parse("2026-10-27 07:00")) { example.run } }

  it "marca para reconectar as contas com o token vencido, na rotina diária" do
    expired = create(:whatsapp_account, status: "connected", token_expires_at: 1.hour.ago)
    pending = create(:whatsapp_account, status: "registration_pending", token_expires_at: 1.day.ago)
    valid = create(:whatsapp_account, status: "connected", token_expires_at: 3.days.from_now)
    forever = create(:whatsapp_account, status: "connected", token_expires_at: nil)
    disconnected = create(:whatsapp_account, status: "disconnected", token_expires_at: 1.day.ago)

    DailyAlertsJob.perform_now

    expect([ expired, pending ].map { |account| account.reload.status }).to all(eq("reconnect_required"))
    expect([ valid, forever ].map { |account| account.reload.status }).to all(eq("connected"))
    expect(disconnected.reload).to be_disconnected
  end

  describe "avisos na central" do
    let!(:admin) { create(:user, :admin) }
    let!(:account) { create(:whatsapp_account, status: "connected", verified_name: "DevBatista", display_phone_number: "+55 11 97070-2026", token_expires_at: Time.zone.parse("2026-11-03 15:00")) }

    def notices = Notification.where(kind: "whatsapp_token_expiring").order(:created_at)

    it "avisa 7 dias antes e no dia, sem repetir se a rotina rodar duas vezes" do
      travel_to(Time.zone.parse("2026-10-26 07:00"))
      described_class.perform_now
      expect(notices).to be_empty # 8 dias antes

      travel_to(Time.zone.parse("2026-10-27 07:00"))
      2.times { described_class.perform_now }
      expect(notices.sole).to have_attributes(user: admin, level: "warn", notifiable: account, path: "/technology/integrations/whatsapp",
                                              title: "O acesso do WhatsApp de DevBatista · +55 11 97070-2026 vence em 7 dias (03/11/2026).")

      travel_to(Time.zone.parse("2026-10-30 07:00"))
      described_class.perform_now
      expect(notices.count).to eq(1) # o de atenção sai uma vez só

      travel_to(Time.zone.parse("2026-11-03 07:00"))
      2.times { described_class.perform_now }
      expect(notices.last).to have_attributes(level: "crit", title: "O acesso do WhatsApp de DevBatista · +55 11 97070-2026 vence hoje. Conecte o número de novo para continuar enviando.")
      expect(notices.count).to eq(2)
    end

    it "com token renovado (nova data), avisa de novo; conta desconectada não recebe aviso" do
      described_class.perform_now
      account.update!(token_expires_at: Time.zone.parse("2026-11-02 15:00"))
      described_class.perform_now
      expect(notices.count).to eq(2)

      create(:whatsapp_account, status: "disconnected", token_expires_at: 3.days.from_now)
      expect { described_class.perform_now }.not_to change(Notification, :count)
    end
  end

  it "avisa a partir de 7 dias do fim" do
    account = build(:whatsapp_account, token_expires_at: 7.days.from_now)
    expect(account).to be_token_expiring
    expect(account).not_to be_token_expired

    account.token_expires_at = 8.days.from_now
    expect(account).not_to be_token_expiring

    account.token_expires_at = 1.minute.ago
    expect(account).to be_token_expired
    expect(account).not_to be_token_expiring
  end
end
