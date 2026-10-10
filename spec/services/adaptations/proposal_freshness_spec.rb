require "rails_helper"

RSpec.describe "CYF-6 proposal freshness", type: :service, generated_workouts: true do
  before { travel_to Time.zone.local(2026, 10, 5, 12) }

  let(:plan) { create(:training_plan, starts_on: Date.current - 14, ends_on: Date.current + 69, progression_mode: :continuous, hard_weeks_before_recovery: nil) }
  let(:phase) { create(:plan_phase, training_plan: plan, starts_on: plan.starts_on, ends_on: plan.ends_on) }
  let(:target) { generated_workout(plan: plan, phase: phase, date: Date.current + 10, level: 5, duration: 90) }
  let(:template) { create(:availability_template, training_plan: plan, effective_from: plan.starts_on) }
  let(:slot) { create(:availability_slot, availability_template: template, weekday: 2, intent: :threshold, duration_minutes: 90) }

  def state
    [ plan.reload.attributes,
      plan.planned_workouts.order(:id).map { |workout| [ workout.attributes, workout.workout_steps.map(&:attributes), workout.workout_feedback&.attributes ] },
      plan.adaptation_proposals.order(:id).map(&:attributes) ]
  end

  def expect_unavailable(proposal, message = nil)
    before = state
    expect { Adaptations::ProposalApplier.new(proposal).accept! }.to raise_error(Adaptations::ProposalFreshness::Unavailable, message)
    expect(state).to eq(before)
    expect(proposal.reload).to be_persisted
  end

  %i[feedback material_change].each do |type|
    context "with a #{type} proposal" do
      let(:source) { generated_workout(plan: plan, phase: phase, date: type == :feedback ? Date.current : Date.current + 8, duration: 90) }
      let(:proposal) do
        slot
        target
        if type == :feedback
          Adaptations::CompletionRecorder.new(workout: source, rpe: 10, completion_quality: :as_planned).call
        else
          Planning::MaterialChangeProposal.new(source).replace!(material_change: true)
        end
      end

      it "captures a baseline and allows atomic acceptance just before expiry" do
        expect(proposal.payload.fetch("freshness")).to include("version" => 1, "digest" => a_string_matching(/\A[0-9a-f]{64}\z/))
        travel_to proposal.expires_at - 1.second
        history = source.reload.attributes if type == :feedback
        Adaptations::ProposalApplier.new(proposal).accept!
        expect(AdaptationProposal).not_to exist(proposal.id)
        expect(source.reload.attributes).to eq(history) if history
      end

      [ 0, 1 ].each do |seconds|
        it "rejects #{seconds.zero? ? 'exactly at' : 'after'} expiry without changing workouts or bias" do
          travel_to proposal.expires_at + seconds.seconds
          expect_unavailable(proposal, Adaptations::ProposalFreshness::EXPIRED_MESSAGE)
          before = state.first(2)
          Adaptations::ProposalApplier.new(proposal).reject!
          expect(state.first(2)).to eq(before)
        end
      end

      {
        "canonical target edits" => ->(target) { Workouts::ManualEditor.new(target).apply!(action: :easier) },
        "step edits" => ->(target) { target.workout_steps.first.update!(label: "Changed cue") },
        "a move within the horizon" => ->(target) { target.update!(scheduled_on: target.scheduled_on + 1) },
        "a move outside the horizon" => ->(target) { target.update!(scheduled_on: target.scheduled_on + 20) },
        "a missed target" => ->(target) { Planning::MissedWorkoutResolver.new(target).resolve!(mode: :leave_unchanged) },
        "a completed target" => ->(target) { Adaptations::CompletionRecorder.new(workout: target, rpe: 8, completion_quality: :as_planned).call },
        "a deleted target" => ->(target) { Workouts::Remover.new(target).call }
      }.each do |description, change|
        it "rejects #{description} without partially applying the proposal" do
          proposal
          change.call(target)
          expect_unavailable(proposal)
        end
      end

      it "rejects a replaced target even when its date and prescription are retained" do
        proposal
        date = target.scheduled_on
        target.destroy!
        generated_workout(plan: plan, phase: phase, date: date, level: 5, duration: 90)
        expect_unavailable(proposal)
      end

      it "rejects changed availability" do
        proposal
        slot.update!(duration_minutes: 120)
        expect_unavailable(proposal, Adaptations::ProposalFreshness::STALE_MESSAGE)
      end

      it "rejects actual schedule regeneration after an availability change" do
        proposal
        Planning::AvailabilityChanger.new(plan: plan, slots: [ { weekday: 2, intent: :endurance, duration_minutes: 60 } ], effective_from: target.scheduled_on, scope: :from_date).apply!
        expect_unavailable(proposal)
      end

      it "rejects relevant time off and return-ramp changes" do
        proposal
        create(:time_off_period, training_plan: plan, starts_on: target.scheduled_on - 2, ends_on: target.scheduled_on - 1, reason: :illness, return_ramp_days: 7)
        expect_unavailable(proposal, Adaptations::ProposalFreshness::STALE_MESSAGE)
      end

      it "rejects a modified return ramp on an existing period" do
        period = create(:time_off_period, training_plan: plan, starts_on: Date.current + 4, ends_on: Date.current + 6, reason: :illness, return_ramp_days: 7)
        proposal
        period.update!(return_ramp_days: 10)
        expect_unavailable(proposal, Adaptations::ProposalFreshness::STALE_MESSAGE)
      end

      it "rejects changed progression state and archived plans" do
        proposal
        plan.update!(progression_state: { "intensity_bias" => -1 })
        expect_unavailable(proposal, Adaptations::ProposalFreshness::STALE_MESSAGE)
        plan.update!(status: :archived)
        expect_unavailable(proposal, Adaptations::ProposalFreshness::UNAVAILABLE_MESSAGE)
      end

      it "ignores metrics-only FTP recalculation and reads the owner's new FTP" do
        profile = create(:rider_profile, user: plan.user, ftp_watts: 260)
        proposal
        profile.update!(ftp_watts: 310)
        Planning::FtpRecalculator.new(profile: profile).call
        expect(Adaptations::ProposalFreshness.new(proposal).unavailability_message).to be_nil
        expect(Adaptations::ProposalComparison.new(proposal).call.ftp_watts).to eq(310) if type == :feedback
        Adaptations::ProposalApplier.new(proposal).accept!
      end

      it "does not invalidate for another rider or distant unrelated schedule changes" do
        proposal
        other = create(:training_plan)
        other.update!(progression_state: { "intensity_bias" => 2 })
        create(:time_off_period, training_plan: other)
        generated_workout(plan: plan, phase: phase, date: Date.current + 50, duration: 90)
        create(:time_off_period, training_plan: plan, starts_on: Date.current + 55, ends_on: Date.current + 57)
        plan.update!(progression_state: { "unrelated_metadata" => "updated" })
        # A later change may close the old template without changing any of
        # this proposal's applicable dates.
        template.update!(effective_until: Date.current + 40)
        expect(Adaptations::ProposalFreshness.new(proposal).unavailability_message).to be_nil
      end

      it "does not trust legacy or unknown-version freshness metadata" do
        proposal.update!(payload: proposal.payload.except("freshness"))
        expect_unavailable(proposal, Adaptations::ProposalFreshness::LEGACY_MESSAGE)
        proposal.update!(payload: proposal.payload.merge("freshness" => { "version" => 99, "digest" => "unknown" }))
        expect_unavailable(proposal, Adaptations::ProposalFreshness::LEGACY_MESSAGE)
      end

      it "USR-004 validates and accepts through the explicit owning plan despite another Current.user" do
        other_plan = create(:training_plan, starts_on: plan.starts_on, ends_on: plan.ends_on, progression_state: { "intensity_bias" => 2 })
        other_profile = create(:rider_profile, user: other_plan.user, ftp_watts: 410)
        other_history = create(:planned_workout, :completed, training_plan: other_plan, scheduled_on: Date.current - 1)
        other_proposal = create(:adaptation_proposal, training_plan: other_plan)
        before = [ other_plan.attributes, other_profile.attributes, other_history.attributes, other_history.workout_steps.map(&:attributes), other_proposal.attributes ]
        proposal
        Current.session = other_plan.user.sessions.create!
        expect(Adaptations::ProposalFreshness.new(proposal).unavailability_message).to be_nil
        Adaptations::ProposalApplier.new(proposal).accept!
        expect([ other_plan.reload.attributes, other_profile.reload.attributes, other_history.reload.attributes, other_history.workout_steps.map(&:attributes), other_proposal.reload.attributes ]).to eq(before)
      ensure
        Current.reset
      end

      it "cannot apply twice when an old instance is reused" do
        copy = AdaptationProposal.find(proposal.id)
        Adaptations::ProposalApplier.new(proposal).accept!
        before = state
        expect { Adaptations::ProposalApplier.new(copy).accept! }.to raise_error(ActiveRecord::RecordNotFound)
        expect(state).to eq(before)
      end
    end
  end

  it "invalidates a material replan after its changed source is edited again" do
    target
    proposal = Planning::MaterialChangeProposal.new(target).replace!(material_change: true)
    Workouts::ManualEditor.new(target).apply!(action: :same)
    expect_unavailable(proposal, Adaptations::ProposalFreshness::STALE_MESSAGE)
  end

  it "CYF-12 invalidates a changed recent pre-break level despite an older higher maximum" do
    generated_workout(plan: plan, phase: phase, date: Date.current - 13, level: 7, duration: 120)
    recent = generated_workout(plan: plan, phase: phase, date: Date.current - 9, level: 4, duration: 90)
    create(:time_off_period, training_plan: plan, starts_on: Date.current - 4, ends_on: Date.current - 2, reason: :illness, return_ramp_days: 16)
    proposal = Planning::MaterialChangeProposal.new(target).replace!(material_change: true)
    Workouts::ManualEditor.new(recent).apply!(action: :easier)
    expect_unavailable(proposal, Adaptations::ProposalFreshness::STALE_MESSAGE)
  end

  it "validates every feedback target before editing any of them or changing bias" do
    first = generated_workout(plan: plan, phase: phase, date: Date.current + 2, duration: 90)
    proposal = Adaptations::ProposalCreator.new(plan).create!(
      reason: "Reduce load",
      payload: {
                  "changes" => [ first, target ].map { |item| { "planned_workout_id" => item.id, "progression_level" => 2 } }, "progression_bias" => -1 })
    Workouts::ManualEditor.new(target).apply!(action: :easier)
    expect_unavailable(proposal, Adaptations::ProposalFreshness::STALE_MESSAGE)
  end

  it "invalidates a proposal when its preceding comparable load reference changes" do
    reference = generated_workout(plan: plan, phase: phase, date: Date.current + 2, level: 5, duration: 90)
    proposal = Adaptations::ProposalCreator.new(plan).create!(
      reason: "Reduce load",
      payload: { "changes" => [ { "planned_workout_id" => target.id, "progression_level" => 4 } ] })
    Workouts::ManualEditor.new(reference).apply!(action: :longer)
    expect_unavailable(proposal, Adaptations::ProposalFreshness::STALE_MESSAGE)
  end
end
