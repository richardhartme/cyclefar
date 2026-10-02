require "rails_helper"

RSpec.describe "CYF-6 concurrent proposal acceptance", type: :model, generated_workouts: true do
  uses_transaction "applies workouts and bias once across simultaneous acceptance requests"

  it "applies workouts and bias once across simultaneous acceptance requests" do
    user = create(:user)
    plan = create(:training_plan, user: user, starts_on: Date.current, ends_on: Date.current + 69)
    phase = create(:plan_phase, training_plan: plan, starts_on: plan.starts_on, ends_on: plan.ends_on)
    target = generated_workout(plan: plan, phase: phase, date: Date.current + 2, level: 5, duration: 90)
    proposal = Adaptations::ProposalCreator.new(plan).create!(
      reason: "Reduce load",
      payload: {
                  "changes" => [ { "planned_workout_id" => target.id, "progression_level" => 4 } ], "progression_bias" => -1 })
    preview = Adaptations::ProposalComparison.new(proposal).call.changes.first.preview
    ready = Queue.new
    start = Queue.new
    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          own_instance = AdaptationProposal.find(proposal.id)
          ready << true
          start.pop
          begin
            Adaptations::ProposalApplier.new(own_instance).accept!
            :applied
          rescue ActiveRecord::RecordNotFound
            :gone
          end
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    expect(threads.map(&:value)).to contain_exactly(:applied, :gone)
    expect(plan.reload.progression_state).to eq("intensity_bias" => -1)
    expect(target.reload.progression_level).to eq(preview.definition.progression_level)
    expect(target.workout_steps.map { |step| Workouts::StepDefinition.from(step).to_h }).to eq(preview.definition.steps.map(&:to_h))
    expect(AdaptationProposal).not_to exist(proposal.id)
  ensure
    threads&.each(&:join)
    plan&.destroy!
    user&.destroy!
  end
end
