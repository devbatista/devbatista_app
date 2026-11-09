require "rails_helper"

RSpec.describe "Rotinas das visitas do site" do
  describe SiteVisitSaltCleanupJob do
    it "apaga os sais dos dias anteriores e mantém o de hoje" do
      today = Date.new(2026, 11, 9)
      [ today - 2, today - 1, today ].each { |day| SiteVisitSalt.create!(day: day, salt: SecureRandom.hex(32)) }

      described_class.perform_now(today)

      expect(SiteVisitSalt.pluck(:day)).to eq([ today ])
    end
  end

  describe AiAgentIpRangesJob do
    it "atualiza as faixas de IP dos robôs de IA" do
      allow(SiteVisits::AiAgentIpRanges).to receive(:refresh_all)
      described_class.perform_now
      expect(SiteVisits::AiAgentIpRanges).to have_received(:refresh_all)
    end
  end

  describe SiteVisitSalt do
    it "cria o sal do dia uma vez só, aleatório" do
      salt = described_class.for(Date.new(2026, 11, 9))

      expect(salt).to match(/\A\h{64}\z/)
      expect(described_class.for(Date.new(2026, 11, 9))).to eq(salt)
      expect(described_class.for(Date.new(2026, 11, 10))).not_to eq(salt)
    end
  end
end
