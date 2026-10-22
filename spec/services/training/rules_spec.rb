require "rails_helper"

RSpec.describe Training::Rules do
  describe ".reduced_duration" do
    it "scales and rounds the duration" do
      expect(described_class.reduced_duration(90, 0.7)).to eq(63)
    end

    it "never goes below the minimum duration" do
      expect(described_class.reduced_duration(40, 0.5)).to eq(described_class::MINIMUM_DURATION_MINUTES)
    end
  end
end
