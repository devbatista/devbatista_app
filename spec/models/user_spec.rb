require "rails_helper"

RSpec.describe User do
  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to belong_to(:role) }

  it "não deixa entrar usuário desativado" do
    user = build(:user, :inactive)
    expect(user.active_for_authentication?).to be(false)
    expect(user.inactive_message).to eq(:deactivated)
  end

  it "guarda o custo por hora em centavos" do
    user = build(:user, hourly_cost: "95,50")
    expect(user.hourly_cost_cents).to eq(9550)
    expect(user.hourly_cost).to eq(95.5)
  end

  it "monta as iniciais com o primeiro e o último nome" do
    expect(build(:user, name: "Carla Mendes Souza").initials).to eq("CS")
    expect(build(:user, name: "Rafael").initials).to eq("R")
  end

  it "normaliza o e-mail" do
    expect(build(:user, email: "  Ana@DevBatista.com ").email).to eq("ana@devbatista.com")
  end

  describe "auditoria" do
    it "registra a criação sem dados sensíveis" do
      user = create(:user)
      log = AuditLog.find_by!(auditable: user, action: "create")
      expect(log.area).to eq("administracao")
      expect(log.changeset.keys).to include("name", "email")
      expect(log.changeset.keys).not_to include("encrypted_password")
    end

    it "registra a alteração com valor anterior e novo" do
      user = create(:user, name: "Ana")
      user.update!(name: "Ana Souza")
      log = AuditLog.where(auditable: user, action: "update").last
      expect(log.changeset).to eq("name" => [ "Ana", "Ana Souza" ])
    end

    it "não registra mudança só em campos ignorados" do
      user = create(:user)
      expect { user.update!(sign_in_count: 3) }.not_to change(AuditLog, :count)
    end
  end
end
