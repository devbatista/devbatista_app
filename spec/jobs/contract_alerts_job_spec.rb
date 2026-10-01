require "rails_helper"

RSpec.describe ContractAlertsJob do
  let(:today) { Date.new(2026, 9, 17) }
  let!(:admin) { create(:user, :admin) }
  let!(:comercial) { create(:user, :comercial) }
  let!(:suporte) { create(:user, :suporte) }

  def contract_ending_in(days, **attrs)
    create(:contract, start_date: today - 1.year, end_date: today + days, **attrs)
  end

  it "muda para Próximo do vencimento dentro da maior antecedência" do
    near = contract_ending_in(45)
    far = contract_ending_in(90)
    described_class.perform_now(today)
    expect(near.reload).to be_expiring
    expect(far.reload).to be_active
  end

  it "avisa Comercial e Administrador no marco de 30 dias, e mais ninguém" do
    contract = contract_ending_in(30)
    described_class.perform_now(today)
    recipients = Notification.where(notifiable: contract).map(&:user)
    expect(recipients).to contain_exactly(admin, comercial)
    expect(Notification.last.title).to include("vence em 30 dias")
  end

  it "não repete o alerta se a rotina rodar duas vezes no mesmo dia" do
    contract_ending_in(15)
    expect { 2.times { described_class.perform_now(today) } }.to change(Notification, :count).by(2)
  end

  it "envia e-mail só para quem mantém a preferência ligada" do
    comercial.update!(email_preferences: { "contract_expiring" => false })
    contract_ending_in(30)
    expect { described_class.perform_now(today) }.to have_enqueued_mail(NotificationMailer, :alert).once
  end

  it "encerra o contrato vencido sem renovação automática" do
    manual = create(:contract, status: "expiring", renewal: "manual", start_date: today - 1.year, end_date: today - 1)
    automatic = create(:contract, status: "expiring", renewal: "automatic", start_date: today - 1.year, end_date: today - 1)
    described_class.perform_now(today)
    expect(manual.reload).to be_ended
    expect(automatic.reload).to be_expiring
  end
end
