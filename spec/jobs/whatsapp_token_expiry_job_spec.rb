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
