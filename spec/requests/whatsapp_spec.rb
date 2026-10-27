require "rails_helper"

RSpec.describe "WhatsApp" do
  it "mostra o grupo no menu, ainda em construção, só para quem tem a área" do
    sign_in create(:user, :admin)
    get root_path
    menu = response.body[/<aside class="side".*?<\/aside>/m]
    expect(menu).to include("WhatsApp", "Conversas", "Templates", "em breve")

    sign_out :user
    sign_in create(:user, :comercial)
    get root_path
    expect(response.body[/<aside class="side".*?<\/aside>/m]).not_to include("WhatsApp")
  end
end
