require "rails_helper"

RSpec.describe "Permissões do WhatsApp" do
  let(:admin) { create(:user, :admin) }
  let(:comercial) { create(:user, :comercial) }
  let(:records) do
    account = create(:whatsapp_account)
    conversation = create(:whatsapp_conversation, account: account)
    [ conversation, create(:whatsapp_message, conversation: conversation), create(:whatsapp_template, account: account) ]
  end

  def policy(user, record)
    Pundit.policy!(user, record)
  end

  it "na v1, só o administrador tem a área" do
    expect(Role::AREAS).to include("whatsapp" => "WhatsApp")
    expect(Role::DEFAULTS.except("admin").values.map { |attrs| attrs[:permissions]["whatsapp"] }.uniq).to eq([ nil ])
    expect(admin.role.level_for("whatsapp")).to eq("full")
    expect(comercial.role.level_for("whatsapp")).to eq("none")
  end

  it "o administrador lê, escreve e conecta números" do
    (records + [ create(:whatsapp_account) ]).each do |record|
      expect(policy(admin, record)).to have_attributes(index?: true, show?: true, create?: true, update?: true, destroy?: true)
    end
  end

  it "o Comercial não vê nada enquanto a área não for liberada" do
    (records + [ create(:whatsapp_account) ]).each do |record|
      expect(policy(comercial, record)).to have_attributes(index?: false, create?: false, update?: false)
    end
    expect(Pundit.policy_scope!(comercial, WhatsappConversation)).to be_empty
    expect(Pundit.policy_scope!(admin, WhatsappConversation)).to contain_exactly(records.first)
  end

  it "liberada com edição, o perfil conversa e cuida de templates, mas não conecta números" do
    comercial.role.update!(permissions: comercial.role.permissions.merge("whatsapp" => "edit"))
    conversation, message, template = records
    [ conversation, message, template ].each { |record| expect(policy(comercial, record)).to have_attributes(show?: true, create?: true) }
    expect(policy(comercial, conversation.account)).to have_attributes(show?: true, create?: false, update?: false, destroy?: false)
  end
end
