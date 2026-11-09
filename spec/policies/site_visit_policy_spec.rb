require "rails_helper"

RSpec.describe SiteVisitPolicy do
  it "na v1, só o administrador tem a área de marketing, e só para ler" do
    expect(Role::AREAS).to include("marketing" => "Marketing")
    expect(Role::DEFAULTS.except("admin").values.map { |attrs| attrs[:permissions]["marketing"] }.uniq).to eq([ nil ])

    expect(Pundit.policy!(create(:user, :admin), :site_visit).index?).to be(true)
    expect(Pundit.policy!(create(:user, :comercial), :site_visit).index?).to be(false)
    expect(Pundit.policy!(create(:user, role: create(:role, permissions: { "marketing" => "read" })), :site_visit).index?).to be(true)
  end
end
