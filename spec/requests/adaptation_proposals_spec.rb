require "rails_helper"

RSpec.describe "Feedback proposal comparisons", type: :request, generated_workouts: true do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }
  let(:plan) { create(:training_plan, user: user, starts_on: Date.current - 7, ends_on: Date.current + 70) }
  let(:phase) { create(:plan_phase, training_plan: plan, ends_on: plan.ends_on) }
  let(:other_plan) { create(:training_plan, user: other_user, starts_on: plan.starts_on, ends_on: plan.ends_on) }
  let(:other_phase) { create(:plan_phase, training_plan: other_plan, ends_on: other_plan.ends_on) }
  let(:target) { generated_workout(plan: plan, phase: phase, date: Date.current + 2) }
  let(:later) { generated_workout(plan: plan, phase: phase, date: Date.current + 5) }
  let(:other_target) { generated_workout(plan: other_plan, phase: other_phase, date: Date.current + 2) }
  let(:proposal) do
    create(
      :adaptation_proposal,
      :fresh,
      training_plan: plan,
      reason: "Reduce the next two threshold sessions.",
      expires_at: 7.days.from_now,
      payload: { "changes" => [ later, target ].map { |item| { "planned_workout_id" => item.id, "progression_level" => 2 } }, "progression_bias" => -1 })
  end
  let(:other_proposal) do
    create(
      :adaptation_proposal,
      :fresh,
      training_plan: other_plan,
      reason: "Private other-rider adaptation",
      expires_at: 7.days.from_now,
      payload: { "changes" => [ { "planned_workout_id" => other_target.id, "progression_level" => 3 } ], "progression_bias" => 1 })
  end

  before do
    create(:rider_profile, user: user, ftp_watts: 275)
    create(:rider_profile, user: other_user, ftp_watts: 410)
    sign_in_as(user)
  end

  def comparison_section
    Nokogiri::HTML(response.body).css('section[aria-label="Adaptation proposal"]').first
  end

  def persisted_state(owner_plan)
    [ owner_plan.reload.attributes,
      owner_plan.planned_workouts.order(:id).map { |workout| [ workout.attributes, workout.workout_steps.map(&:attributes), workout.workout_feedback&.attributes ] },
      owner_plan.adaptation_proposals.order(:id).map(&:attributes) ]
  end

  it "FBK-002 shows every current/proposed prescription, reason, effective bias and actions without applying it" do
    proposal
    other_proposal
    before = [ persisted_state(plan), persisted_state(other_plan) ]
    2.times do
      get root_path
      expect(response).to have_http_status(:ok)
      section = comparison_section
      expect(section.text).to include(proposal.reason, "Current", "Proposed", "275 W", "0 → -1", "change -1", "Accept all", "Reject all")
      captions = section.css("caption").map(&:text)
      expect(captions.first).to include(target.scheduled_on.to_fs(:long), target.name)
      expect(captions.last).to include(later.scheduled_on.to_fs(:long), later.name)
      expect(section.css("table").length).to eq(2)
      expected = Adaptations::ProposalComparison.new(proposal).call
      section.css("table").zip(expected.changes).each do |table, change|
        expect(table.text).to include(change.preview.definition.name, change.preview.metrics.estimated_tss.round(1).to_s, format("%.2f", change.preview.metrics.estimated_if))
      end
      expect(section.css("a").map { |link| link["href"] }).to eq([ planned_workout_path(target), planned_workout_path(later) ])
      expect(response.body).not_to include(other_proposal.reason)
    end
    expect([ persisted_state(plan), persisted_state(other_plan) ]).to eq(before)
  end

  it "USR-008 previews and accepts only A's changes while preserving both completed histories and B's data" do
    own_history = create(:planned_workout, :completed, training_plan: plan, plan_phase: phase, scheduled_on: Date.current - 2)
    create(:planned_workout, :completed, training_plan: other_plan, plan_phase: other_phase, scheduled_on: Date.current - 2)
    proposal
    other_proposal
    other_before = persisted_state(other_plan)
    own_history_before = own_history.attributes
    own_history_steps = own_history.workout_steps.map(&:attributes)
    get root_path
    preview = Adaptations::ProposalComparison.new(proposal).call
    post accept_adaptation_proposal_path(proposal)
    expect(response).to redirect_to(root_path)
    preview.changes.each do |change|
      expect(change.workout.reload.name).to eq(change.preview.definition.name)
      expect(change.workout.estimated_work_kj.to_f).to be_within(0.001).of(change.preview.metrics.estimated_work_kj)
    end
    expect(plan.reload.progression_state.fetch("intensity_bias")).to eq(-1)
    expect(persisted_state(other_plan)).to eq(other_before)
    expect(own_history.reload.attributes).to eq(own_history_before)
    expect(own_history.workout_steps.reload.map(&:attributes)).to eq(own_history_steps)
    expect(AdaptationProposal.exists?(proposal.id)).to be(false)

    delete session_path
    sign_in_as(other_user)
    get root_path
    expect(comparison_section.text).to include(other_proposal.reason, "410 W")
    expect(response.body).not_to include(proposal.reason)
  end

  it "USR-004 treats foreign and missing proposal IDs identically for both actions" do
    other_proposal
    before = persisted_state(other_plan)
    [ [ :post, :accept_adaptation_proposal_path ], [ :delete, :reject_adaptation_proposal_path ] ].each do |method, route|
      public_send(method, public_send(route, other_proposal))
      expect(response).to have_http_status(:not_found)
      expect(response.body).to eq("")
      public_send(method, public_send(route, 0))
      expect(response).to have_http_status(:not_found)
      expect(response.body).to eq("")
    end
    expect(persisted_state(other_plan)).to eq(before)
  end

  it "rejects only A's proposal without changing either rider's prescriptions" do
    proposal
    other_proposal
    workouts_before = plan.planned_workouts.map(&:attributes)
    other_before = persisted_state(other_plan)
    get root_path
    delete reject_adaptation_proposal_path(proposal)
    expect(response).to redirect_to(root_path)
    expect(plan.planned_workouts.reload.map(&:attributes)).to eq(workouts_before)
    expect(plan.reload.progression_state).to eq({})
    expect(persisted_state(other_plan)).to eq(other_before)
    expect(AdaptationProposal.exists?(proposal.id)).to be(false)
  end

  it "does not render a partial comparison or accept a payload containing another plan's workout" do
    proposal.update!(payload: proposal.payload.merge("changes" => proposal.payload.fetch("changes") + [ { "planned_workout_id" => other_target.id, "progression_level" => 2 } ]))
    other_target.update!(name: "Private foreign target")
    before = [ persisted_state(plan), persisted_state(other_plan) ]
    get root_path
    expect(response).to have_http_status(:ok)
    expect(comparison_section.text).to include(Adaptations::ProposalComparison::UNAVAILABLE_MESSAGE, "Reject all")
    expect(comparison_section.css("table")).to be_empty
    expect(comparison_section.text).not_to include("Accept all", "Private foreign target")
    post accept_adaptation_proposal_path(proposal)
    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to eq(Adaptations::ProposalComparison::UNAVAILABLE_MESSAGE)
    expect([ persisted_state(plan), persisted_state(other_plan) ]).to eq(before)
  end

  it "retains the separate material-change proposal controls" do
    Planning::MaterialChangeProposal.new(target).replace!(material_change: true)
    get root_path
    expect(comparison_section.text).to include("Optional upcoming replan", "Replan upcoming workouts", "Keep rest of plan unchanged")
    expect(comparison_section.css("table")).to be_empty
  end

  it "CYF-6 hides acceptance for expired feedback, explains direct rejection, and dismisses only the owner's proposal" do
    own_history = create(:planned_workout, :completed, training_plan: plan, plan_phase: phase, scheduled_on: Date.current - 2)
    create(:planned_workout, :completed, training_plan: other_plan, plan_phase: other_phase, scheduled_on: Date.current - 2)
    proposal
    other_proposal
    histories = [ own_history.attributes, own_history.workout_steps.map(&:attributes), own_history.workout_feedback.attributes ]
    other_before = persisted_state(other_plan)
    travel_to proposal.expires_at, with_usec: true
    before = persisted_state(plan)
    get root_path
    expect(comparison_section.text).to include(Adaptations::ProposalFreshness::EXPIRED_MESSAGE, "Reject all")
    expect(comparison_section.text).not_to include("Accept all", "Current", "Proposed")
    post accept_adaptation_proposal_path(proposal)
    expect(flash[:alert]).to eq(Adaptations::ProposalFreshness::EXPIRED_MESSAGE)
    expect(persisted_state(plan)).to eq(before)
    delete reject_adaptation_proposal_path(proposal)
    expect(AdaptationProposal).not_to exist(proposal.id)
    expect(persisted_state(other_plan)).to eq(other_before)
    expect([ own_history.reload.attributes, own_history.workout_steps.map(&:attributes), own_history.workout_feedback.attributes ]).to eq(histories)
  end

  it "CYF-6 shows stale guidance after an in-horizon move and preserves both riders on direct acceptance" do
    proposal
    other_proposal
    post move_planned_workout_path(target), params: { scheduled_on: (target.scheduled_on + 1).iso8601 }
    before = [ persisted_state(plan), persisted_state(other_plan) ]
    get root_path
    expect(comparison_section.text).to include(Adaptations::ProposalFreshness::STALE_MESSAGE, "Reject all")
    expect(comparison_section.text).not_to include("Accept all")
    post accept_adaptation_proposal_path(proposal)
    expect(flash[:alert]).to eq(Adaptations::ProposalFreshness::STALE_MESSAGE)
    expect([ persisted_state(plan), persisted_state(other_plan) ]).to eq(before)
  end

  it "CYF-6 renders expired material replans consistently on the calendar and workout page" do
    replan = Planning::MaterialChangeProposal.new(target).replace!(material_change: true)
    other_proposal
    other_before = persisted_state(other_plan)
    travel_to replan.expires_at, with_usec: true
    before = persisted_state(plan)
    get root_path
    expect(comparison_section.text).to include(Adaptations::ProposalFreshness::EXPIRED_MESSAGE, "Keep rest of plan unchanged", "change the workout again")
    expect(comparison_section.css("form").map { |form| form["action"] }).not_to include(accept_adaptation_proposal_path(replan))
    get planned_workout_path(target)
    section = Nokogiri::HTML(response.body).css('section[aria-label="Optional upcoming replan"]').first
    expect(section.text).to include(Adaptations::ProposalFreshness::EXPIRED_MESSAGE, "Keep rest of plan unchanged")
    expect(section.css("form").map { |form| form["action"] }).not_to include(accept_adaptation_proposal_path(replan))
    post accept_adaptation_proposal_path(replan)
    expect(flash[:alert]).to eq(Adaptations::ProposalFreshness::EXPIRED_MESSAGE)
    expect(persisted_state(plan)).to eq(before)
    delete session_path
    sign_in_as(other_user)
    [ [ :post, :accept_adaptation_proposal_path ], [ :delete, :reject_adaptation_proposal_path ] ].each do |method, route|
      public_send(method, public_send(route, replan))
      expect(response).to have_http_status(:not_found)
      foreign = response.body
      public_send(method, public_send(route, 0))
      expect(response).to have_http_status(:not_found)
      expect(response.body).to eq(foreign)
    end
    expect(persisted_state(other_plan)).to eq(other_before)
  end

  it "CYF-6 does not disclose a foreign source in a material replan payload" do
    replan = Planning::MaterialChangeProposal.new(target).replace!(material_change: true)
    replan.update!(payload: replan.payload.merge("source_workout_id" => other_target.id))
    other_target.update!(name: "Private foreign source")
    before = [ persisted_state(plan), persisted_state(other_plan) ]
    get root_path
    expect(comparison_section.text).to include(Adaptations::ProposalFreshness::UNAVAILABLE_MESSAGE)
    expect(response.body).not_to include("Private foreign source", "410 W")
    post accept_adaptation_proposal_path(replan)
    expect(flash[:alert]).to eq(Adaptations::ProposalFreshness::UNAVAILABLE_MESSAGE)
    expect([ persisted_state(plan), persisted_state(other_plan) ]).to eq(before)
  end
end
