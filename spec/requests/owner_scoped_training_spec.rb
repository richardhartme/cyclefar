require "rails_helper"

RSpec.describe "USR-004 owner-scoped training routes", type: :request do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }
  let(:starts_on) { Date.current - 7 }
  let(:ends_on) { Date.current + 70 }

  before { sign_in_as(user) }

  def create_plan(owner)
    create(:training_plan, user: owner, starts_on: starts_on, ends_on: ends_on)
  end

  def create_template(plan, duration: 60)
    template = create(:availability_template, training_plan: plan, effective_from: plan.starts_on)
    create(:availability_slot, availability_template: template, weekday: 2, duration_minutes: duration, intent: :endurance)
    template
  end

  describe "records addressed by ID" do
    let!(:plan) { create_plan(user) }
    let(:other_plan) { create_plan(other_user) }
    let(:other_phase) { create(:plan_phase, training_plan: other_plan, starts_on: starts_on, ends_on: ends_on) }
    let(:other_workout) { create(:planned_workout, :structured, training_plan: other_plan, plan_phase: other_phase, scheduled_on: Date.current + 1) }

    {
      "detail" => [ :get, :planned_workout_path, {} ],
      "shuffle" => [ :post, :shuffle_planned_workout_path, { action_kind: "easier" } ],
      "change" => [ :post, :change_planned_workout_path, { subtype: "recovery", duration_minutes: 60 } ],
      "move" => [ :post, :move_planned_workout_path, { scheduled_on: (Date.current + 2).iso8601 } ],
      "copy" => [ :post, :copy_planned_workout_path, { scheduled_on: (Date.current + 2).iso8601 } ],
      "complete" => [ :post, :complete_planned_workout_path, { rpe: 8, completion_quality: "as_planned" } ],
      "missed resolution" => [ :post, :miss_planned_workout_path, { resolution: "leave_unchanged" } ]
    }.each do |action, (method, route, params)|
      it "returns the same not-found response for another rider's and a missing workout on #{action}" do
        foreign_id = other_workout.id
        original_workout = other_workout.attributes
        original_steps = other_workout.workout_steps.map(&:attributes)

        public_send(method, public_send(route, foreign_id), params: params)
        expect(response).to have_http_status(:not_found)
        foreign_body = response.body
        expect(foreign_body).to be_empty

        public_send(method, public_send(route, 0), params: params)
        expect(response).to have_http_status(:not_found)
        expect(response.body).to eq(foreign_body)
        expect(other_workout.reload.attributes).to eq(original_workout)
        expect(other_workout.workout_steps.map(&:attributes)).to eq(original_steps)
        expect(other_workout.workout_feedback).to be_nil
      end
    end

    [ [ :post, :accept_adaptation_proposal_path ], [ :delete, :reject_adaptation_proposal_path ] ].each do |method, route|
      it "hides another rider's adaptation proposal from #{route}" do
        proposal = create(:adaptation_proposal, training_plan: other_plan)

        public_send(method, public_send(route, proposal))
        expect(response).to have_http_status(:not_found)
        foreign_body = response.body
        expect(foreign_body).to be_empty

        public_send(method, public_send(route, 0))
        expect(response).to have_http_status(:not_found)
        expect(response.body).to eq(foreign_body)
        expect(AdaptationProposal.exists?(proposal.id)).to be(true)
      end
    end

    it "hides another rider's time off from deletion" do
      period = create(:time_off_period, training_plan: other_plan)

      delete time_off_period_path(period)
      expect(response).to have_http_status(:not_found)
      foreign_body = response.body
      expect(foreign_body).to be_empty

      delete time_off_period_path(0)
      expect(response).to have_http_status(:not_found)
      expect(response.body).to eq(foreign_body)
      expect(TimeOffPeriod.exists?(period.id)).to be(true)
    end

    it "allows only the owner's workout and proposal actions when both riders have records" do
      own_phase = create(:plan_phase, training_plan: plan, starts_on: starts_on, ends_on: ends_on)
      own_workout = create(:planned_workout, :structured, training_plan: plan, plan_phase: own_phase, scheduled_on: Date.current + 1)
      other_workout
      own_proposal = create(:adaptation_proposal, training_plan: plan)
      other_proposal = create(:adaptation_proposal, training_plan: other_plan)

      get planned_workout_path(own_workout)
      expect(response).to have_http_status(:ok)
      post complete_planned_workout_path(own_workout), params: { rpe: 5, completion_quality: "as_planned" }
      expect(response).to redirect_to(root_path)
      expect(own_workout.reload).to be_completed
      expect(other_workout.reload).to be_planned

      delete reject_adaptation_proposal_path(own_proposal)
      expect(response).to redirect_to(root_path)
      expect(AdaptationProposal.exists?(own_proposal.id)).to be(false)
      expect(AdaptationProposal.exists?(other_proposal.id)).to be(true)
    end

    it "keeps archived completed history readable only by its owner" do
      own_archive = create(:training_plan, :archived, user: user, starts_on: starts_on, ends_on: ends_on)
      other_archive = create(:training_plan, :archived, user: other_user, starts_on: starts_on, ends_on: ends_on)
      own_phase = create(:plan_phase, training_plan: own_archive, starts_on: starts_on, ends_on: ends_on)
      foreign_phase = create(:plan_phase, training_plan: other_archive, starts_on: starts_on, ends_on: ends_on)
      own_history = create(:planned_workout, :completed, training_plan: own_archive, plan_phase: own_phase, scheduled_on: starts_on + 1)
      foreign_history = create(:planned_workout, :completed, training_plan: other_archive, plan_phase: foreign_phase, scheduled_on: starts_on + 1)

      get planned_workout_path(own_history)
      expect(response).to have_http_status(:ok)
      get planned_workout_path(foreign_history)
      expect(response).to have_http_status(:not_found)
      expect(response.body).to be_empty
    end
  end

  describe "routes without a record ID" do
    it "shows only the signed-in rider's calendar and Settings, and changes only their profile" do
      create_plan(user)
      other_plan = create_plan(other_user)
      other_phase = create(:plan_phase, training_plan: other_plan, starts_on: starts_on, ends_on: ends_on)
      create(:planned_workout, training_plan: other_plan, plan_phase: other_phase, scheduled_on: Date.current + 1, name: "Other rider's secret session")
      create(:rider_profile, user: user, ftp_watts: 250)
      other_profile = create(:rider_profile, user: other_user, ftp_watts: 330)

      get root_path
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Other rider's secret session")

      get settings_path
      expect(response).to have_http_status(:ok)
      expect(Nokogiri::HTML(response.body).at_css('input[name="rider_profile[ftp_watts]"]')["value"]).to eq("250")
      patch settings_path, params: { rider_profile: { ftp_watts: 270 } }
      expect(response).to redirect_to(settings_path)
      expect(user.rider_profile.reload.ftp_watts).to eq(270)
      expect(other_profile.reload.ftp_watts).to eq(330)
      expect(other_profile.ftp_readings).to be_empty
    end

    it "creates and archives only the signed-in rider's plan" do
      other_plan = create_plan(other_user)
      create(:plan_phase, training_plan: other_plan, starts_on: starts_on, ends_on: ends_on)
      create(:rider_profile, user: user, ftp_watts: 260)

      get new_training_plan_path
      expect(response).to have_http_status(:ok)
      expect(Nokogiri::HTML(response.body).at_css('input[name="plan_configuration[ftp_watts]"]')["value"]).to eq("260")

      configuration = {
        goal: "increase_ftp", discipline: "road", starts_on: Date.current.iso8601,
        duration_mode: "preset", duration_months: "3", ftp_watts: "260",
        include_base: "1", progression_mode: "continuous",
        availability: { "2" => { weekday: "2", enabled: "1", duration_minutes: "60", intent: "intervals" } }
      }
      post preview_training_plan_path, params: { plan_configuration: configuration }
      expect(response).to redirect_to(preview_training_plan_path)
      follow_redirect!
      expect(response).to have_http_status(:ok)
      post training_plan_path
      expect(response).to redirect_to(root_path)
      own_plan = user.training_plans.active.sole
      own_phase = own_plan.plan_phases.first
      free_date = (own_phase.starts_on..own_phase.ends_on).find { |date| !own_plan.planned_workouts.exists?(scheduled_on: date) }
      completed = create(:planned_workout, :completed, training_plan: own_plan, plan_phase: own_phase, scheduled_on: free_date)
      expect(other_plan.reload).to be_active

      delete training_plan_path
      expect(response).to redirect_to(root_path)
      expect(own_plan.reload).to be_archived
      expect(completed.reload).to be_completed
      expect(other_plan.reload).to be_active
    end

    it "cannot archive another rider's only active plan" do
      other_plan = create_plan(other_user)

      delete training_plan_path
      expect(response).to have_http_status(:not_found)
      expect(other_plan.reload).to be_active
    end

    it "adds workouts, availability changes and time off only to the signed-in rider's plan" do
      plan = create_plan(user)
      other_plan = create_plan(other_user)
      create(:plan_phase, training_plan: plan, starts_on: starts_on, ends_on: ends_on)
      create(:plan_phase, training_plan: other_plan, starts_on: starts_on, ends_on: ends_on)
      create_template(plan)
      create_template(other_plan, duration: 90)

      get new_planned_workout_path(scheduled_on: Date.current + 2)
      expect(response).to have_http_status(:ok)
      post planned_workouts_path, params: { scheduled_on: Date.current + 2, subtype: "threshold", duration_minutes: 60 }
      expect(response).to redirect_to(root_path)
      expect(plan.planned_workouts.find_by(scheduled_on: Date.current + 2)).to be_present
      expect(other_plan.planned_workouts.find_by(scheduled_on: Date.current + 2)).to be_nil

      get new_availability_change_path
      expect(response).to have_http_status(:ok)
      change = {
        scope: "from_date", effective_from: (Date.current + 7).iso8601,
        slots: { "2" => { weekday: "2", enabled: "1", duration_minutes: "75", intent: "endurance" } }
      }
      post availability_change_path, params: change
      expect(response).to redirect_to(root_path)
      expect(plan.availability_templates.count).to eq(2)
      expect(other_plan.availability_templates.count).to eq(1)

      get new_time_off_period_path
      expect(response).to have_http_status(:ok)
      time_off = { starts_on: Date.current + 14, ends_on: Date.current + 15, reason: "holiday" }
      post time_off_periods_path, params: { time_off_period: time_off }
      expect(response).to redirect_to(root_path)
      expect(plan.time_off_periods.count).to eq(1)
      expect(other_plan.time_off_periods.count).to eq(0)
    end

    it "uses only the signed-in rider's plan and key for manual sync" do
      create_plan(user)
      other_plan = create_plan(other_user)
      create(:rider_profile, user: other_user, ftp_watts: 300, intervals_icu_api_key: "other-rider-key")

      post intervals_icu_sync_path
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to include("Add an Intervals.icu API key in Settings")
      expect(other_plan).to be_active
      expect(IntervalsIcuSync.count).to eq(0)
    end
  end
end
