require "rails_helper"

RSpec.describe Planning::Rules do
  describe ".horizon_end" do
    it "is the last day of the planning horizon starting on the date" do
      expect(described_class.horizon_end(Date.new(2026, 10, 5))).to eq(Date.new(2026, 10, 18))
    end
  end
end
