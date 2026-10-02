require "rails_helper"

RSpec.describe ProposalAlertsJob do
  let(:today) { Date.new(2026, 9, 17) }
  let(:owner) { create(:user, :comercial) }

  it "expira a proposta enviada no dia seguinte ao fim da validade" do
    old = create(:proposal, user: owner, status: "sent", valid_until: today - 1)
    still = create(:proposal, user: owner, status: "viewed", valid_until: today)
    described_class.perform_now(today)
    expect(old.reload).to be_expired
    expect(still.reload).to be_viewed
  end

  it "avisa só o responsável, 3 dias antes, uma vez" do
    proposal = create(:proposal, user: owner, status: "sent", valid_until: today + 3)
    create(:user, :admin)
    expect { 2.times { described_class.perform_now(today) } }.to change(Notification, :count).by(1)
    expect(Notification.last).to have_attributes(user: owner, notifiable: proposal, kind: "proposal_expiring")
  end
end
