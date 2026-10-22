require "rails_helper"

RSpec.describe AvailabilityTemplate do
  let(:plan) { create(:training_plan, starts_on: Date.new(2026, 10, 5), ends_on: Date.new(2026, 12, 6), progression_mode: :continuous, hard_weeks_before_recovery: nil) }

  def template(attrs = {})
    create(:availability_template, { training_plan: plan, effective_from: plan.starts_on }.merge(attrs))
  end

  describe ".for_date" do
    it "returns the template whose window contains the date, inclusive at both ends" do
      earlier = template(effective_until: plan.starts_on + 13)
      later = template(effective_from: plan.starts_on + 14, source: :from_date_change)

      expect(described_class.for_date([ earlier, later ], plan.starts_on + 13)).to eq(earlier)
      expect(described_class.for_date([ earlier, later ], plan.starts_on + 14)).to eq(later)
    end

    it "prefers a one-week override over the ongoing template regardless of list order" do
      ongoing = template
      override = template(effective_from: plan.starts_on + 7, effective_until: plan.starts_on + 13, source: :one_week_override)

      expect(described_class.for_date([ override, ongoing ], plan.starts_on + 8)).to eq(override)
      expect(described_class.for_date([ ongoing, override ], plan.starts_on + 8)).to eq(override)
      expect(described_class.for_date([ ongoing, override ], plan.starts_on + 14)).to eq(ongoing)
    end

    it "prefers the latest effective_from, then the newest record, among overlapping templates" do
      first = template
      versioned = template(effective_from: plan.starts_on + 7, source: :from_date_change)
      duplicate = template(effective_from: plan.starts_on + 7, source: :from_date_change)

      expect(described_class.for_date([ first, versioned ], plan.starts_on + 8)).to eq(versioned)
      expect(described_class.for_date([ duplicate, versioned, first ], plan.starts_on + 8)).to eq(duplicate)
      expect(described_class.for_date([ versioned, duplicate, first ], plan.starts_on + 8)).to eq(duplicate)
    end

    it "returns nil when no template applies" do
      expired = template(effective_until: plan.starts_on + 6)

      expect(described_class.for_date([ expired ], plan.starts_on + 7)).to be_nil
      expect(described_class.for_date([], plan.starts_on)).to be_nil
    end
  end
end
