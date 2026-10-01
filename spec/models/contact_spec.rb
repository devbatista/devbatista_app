require "rails_helper"

RSpec.describe Contact do
  let(:company) { create(:company) }

  it "mantém um único contato principal por empresa" do
    first = create(:contact, company: company, primary: true)
    second = create(:contact, company: company, primary: true)
    expect(first.reload.primary?).to be(false)
    expect(company.reload.primary_contact).to eq(second)
  end

  it "não mexe no principal de outra empresa" do
    other = create(:contact, primary: true)
    create(:contact, company: company, primary: true)
    expect(other.reload.primary?).to be(true)
  end

  it "é garantido também no banco" do
    create(:contact, company: company, primary: true)
    expect { Contact.insert!({ company_id: company.id, name: "X", primary: true, created_at: Time.current, updated_at: Time.current }) }
      .to raise_error(ActiveRecord::RecordNotUnique)
  end
end
