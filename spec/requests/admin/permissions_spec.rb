require "rails_helper"

RSpec.describe "Administração → Permissões" do
  before { Role.seed_defaults! }

  let(:admin) { create(:user, :admin) }

  it "salva a matriz e mantém o administrador com acesso total" do
    sign_in admin
    patch admin_permissions_path, params: {
      permissions: {
        "comercial" => Role::AREAS.keys.index_with("none").merge("financeiro" => "read"),
        "admin" => { "financeiro" => "none" }
      }
    }
    expect(response).to redirect_to(admin_permissions_path)
    expect(Role.find_by(key: "comercial").level_for("financeiro")).to eq("read")
    expect(Role.find_by(key: "comercial").level_for("comercial")).to eq("none")
    expect(Role.find_by(key: "admin").level_for("financeiro")).to eq("full")
  end

  it "vale no próximo clique: sem permissão, a rota responde 403" do
    user = create(:user, :financeiro)
    sign_in user
    get root_path
    expect(response).to have_http_status(:ok)

    user.role.update!(permissions: user.role.permissions.except("dashboard"))
    get root_path
    expect(response).to have_http_status(:forbidden)
  end
end
