require "rails_helper"

RSpec.describe "WhatsApp" do
  it "mostra o grupo no menu, com o contador de não lidas, só para quem tem a área" do
    account = create(:whatsapp_account)
    create(:whatsapp_conversation, account: account, unread_count: 2, last_message_at: 1.minute.ago)
    create(:whatsapp_conversation, account: account, unread_count: 1, last_message_at: nil) # da agenda, sem mensagem
    sign_in create(:user, :admin)
    get root_path
    menu = response.body[/<aside class="side".*?<\/aside>/m]
    expect(menu).to include("WhatsApp", "Conversas", "Templates", %(href="/whatsapp/conversations"), %(id="whatsapp_menu_counter" class="n">1<))
    expect(menu).to include('channel="WhatsappStreamsChannel"').and(exclude("em breve"))

    sign_out :user
    sign_in create(:user, :comercial)
    get root_path
    expect(response.body[/<aside class="side".*?<\/aside>/m]).not_to include("WhatsApp")
  end
end
