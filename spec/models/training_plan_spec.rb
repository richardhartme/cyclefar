require "rails_helper"

RSpec.describe TrainingPlan do
  describe "#intensity_bias" do
    it "defaults to zero" do
      expect(build(:training_plan, progression_state: {}).intensity_bias).to eq(0)
    end

    it "reads the stored bias as an integer" do
      expect(build(:training_plan, progression_state: { "intensity_bias" => "-1" }).intensity_bias).to eq(-1)
    end
  end
end
