require "rails_helper"

RSpec.describe "Comercial" do
  describe Lead do
    it "exige a origem e preenche a data de entrada" do
      lead = Lead.new(name: "Paulo", user: create(:user))
      expect(lead).not_to be_valid
      expect(lead.errors[:origin]).to be_present
      lead.origin = "whatsapp"
      lead.valid?
      expect(lead.entered_on).to eq(Date.current)
    end

    it "exige motivo da lista para marcar como perdido" do
      lead = create(:lead)
      expect(lead.update(status: "lost")).to be(false)
      expect(lead.update(status: "lost", lost_reason: "Inventado")).to be(false)
      lead.mark_lost!(reason: "Preço")
      expect(lead.reload).to be_status_lost
      expect(lead.lost_at).to be_present
    end
  end

  describe Opportunity do
    it "sugere a probabilidade pela etapa" do
      opp = create(:opportunity)
      expect(opp.probability).to eq(25)
      opp.update!(stage: "negotiation")
      expect(opp.probability).to eq(75)
    end

    it "mantém a probabilidade informada junto com a mudança de etapa" do
      opp = create(:opportunity)
      opp.update!(stage: "proposal", probability: 60)
      expect(opp.probability).to eq(60)
    end

    it "calcula a previsão ponderada" do
      expect(build(:opportunity, estimated_value_cents: 1_400_000, probability: 60).weighted_cents).to eq(840_000)
    end

    it "fixa 100% e a data ao fechar" do
      opp = create(:opportunity)
      opp.update!(stage: "won", probability: 30)
      expect(opp.probability).to eq(100)
      expect(opp.closed_on).to eq(Date.current)
    end
  end

  describe Proposal do
    it "numera por ano e soma os itens" do
      first = create(:proposal)
      second = create(:proposal)
      expect(second.number).to eq(first.number + 1)
      expect(first.code).to eq("#P-#{Date.current.year}-#{format('%03d', first.number)}")
      second.items.create!(service: create(:service), price_cents: 50_000)
      second.save!
      expect(second.reload.total_cents).to eq(350_000)
    end

    it "sugere o contato principal da empresa" do
      company = create(:company)
      contact = create(:contact, company: company, primary: true)
      expect(create(:proposal, company: company).contact).to eq(contact)
    end

    it "exige cliente ou lead" do
      proposal = build(:proposal, company: nil, lead: nil)
      expect(proposal).not_to be_valid
    end

    it "usa o preço padrão do catálogo no item" do
      service = create(:service, default_price_cents: 550_000, kind: "project")
      item = create(:proposal).items.create!(service: service)
      expect([ item.price_cents, item.default_price_cents, item.recurrence ]).to eq([ 550_000, 550_000, "one_off" ])
    end
  end

  describe LeadConversion do
    let(:lead) { create(:lead, status: "qualified", company_name: "Transportes Lima", name: "Paulo Lima") }

    it "cria empresa, contato principal e oportunidade a partir do lead" do
      conversion = LeadConversion.from(lead)
      conversion.cnpj = "11.222.333/0001-81"
      expect(conversion.save).to be(true)
      expect(lead.reload).to be_status_converted
      expect(conversion.company.primary_contact.name).to eq("Paulo Lima")
      expect(conversion.opportunity).to have_attributes(stage: "meeting", lead: lead, company: conversion.company)
    end

    it "vincula à empresa existente com o mesmo CNPJ" do
      existing = create(:company, cnpj: "11.222.333/0001-81")
      conversion = LeadConversion.from(lead)
      conversion.cnpj = "11222333000181"
      expect(conversion.existing_company).to eq(existing)
      expect { conversion.save }.not_to change(Company, :count)
      expect(conversion.company).to eq(existing)
    end

    it "não converte lead perdido" do
      lead.mark_lost!(reason: "Prazo")
      conversion = LeadConversion.from(lead)
      conversion.cnpj = "11.222.333/0001-81"
      expect(conversion.save).to be(false)
    end
  end

  describe ProposalApproval do
    let(:company) { create(:company, status: "prospect") }
    let(:opportunity) { create(:opportunity, company: company, stage: "proposal") }
    let(:proposal) do
      create(:proposal, company: company, opportunity: opportunity, status: "sent").tap do |p|
        p.items.create!(service: create(:service, kind: "project"), price_cents: 1_200_000, recurrence: "one_off")
        p.save!
      end
    end

    it "gera contrato e serviços contratados e fecha o negócio" do
      approval = ProposalApproval.new(proposal: proposal, start_date: Date.current, due_day: 10)
      expect(approval.save).to be(true)
      contract = approval.contract
      expect(contract).to have_attributes(company: company, periodicity: "monthly", value_cents: 300_000)
      expect(contract.customer_services.count).to eq(2)
      expect(company.reload).to be_active
      expect(company.mrr_cents).to eq(300_000)
      expect(opportunity.reload).to be_stage_won
      expect(proposal.reload).to have_attributes(status: "approved", contract: contract)
    end

    it "não aprova rascunho nem proposta só para lead" do
      draft = create(:proposal, company: company)
      expect(ProposalApproval.new(proposal: draft).save).to be(false)
      lead_only = create(:proposal, company: nil, lead: create(:lead), status: "sent")
      approval = ProposalApproval.new(proposal: lead_only)
      expect(approval.save).to be(false)
      expect(approval.errors.full_messages).to include("Converta o lead em cliente antes de aprovar")
    end
  end
end
