# CycleFar Application Architecture

This maps the implemented application. [REQUIREMENTS.md](REQUIREMENTS.md) and [TRAINING_ENGINE.md](TRAINING_ENGINE.md) define the behaviour it implements.

## Application identity and stack

- Module `CycleFar`, project `cycle_far`; domain classes stay brand-neutral.
- Ruby 4.0.6, Rails 8.1.4, PostgreSQL, server-rendered ERB, Turbo, Tailwind CSS with daisyUI, import maps and plain Ruby domain services.
- Stimulus handles presentation only (for example, the plan form's goal-dependent fields). No training calculation runs in JavaScript.
- Rails-generated authentication gates private requests.
- Intervals.icu export is manual; an FTP change refreshes already-exported workouts in the foreground. There are no background sync or generation jobs.

Services live under `app/services/`:

```text
app/services/
  planning/       # configuration, rules, load control, previews, persistence, calendar and replanning
  training/       # workout rules, power bands, ladders and pure progression calculation
  workouts/      # canonical definitions, generators, editing, adding and copying
  metrics/       # calculations over canonical steps
  adaptations/   # completion, feedback, comparisons, load limiting and acceptance/rejection
  accounts/      # controlled operator provisioning and password setup delivery
  settings/      # transactional profile and FTP changes
  intervals_icu/ # serializer, HTTP client and calendar reconciliation
```

Avoid repository layers, command buses, event sourcing, GraphQL and front-end SPAs.

## Authentication boundary

- `ApplicationController` includes the generated `Authentication` concern, which redirects requests without a valid signed `session_id` cookie to sign-in and returns there afterwards.
- `HomeController#index` is public: signed-out visitors see the welcome page, signed-in riders their calendar.
- `SessionsController` creates and destroys database-backed `Session`s; sign-out also clears the Rails session. `Current.session` and `Current.user` expose them per request.
- `PasswordsController` handles reset requests and token updates; a successful reset destroys the user's sessions.
- `RegistrationsController` creates a `User` with a confirmed password, signs them in and redirects to the calendar. It rejects signed-in visitors.
- Sign-in, reset requests and registration are rate-limited.
- `Accounts::Provision` and an operator task create riders with a random password and email a setup link; the task needs an explicit flag. See [ACCOUNT_ACCESS.md](ACCOUNT_ACCESS.md) for mail settings and the procedure.

## Independent-rider boundary

There is no singleton profile or global active plan; everything resolves from `Current.user`.

- Settings locks the owning user row; plan creation receives the user explicitly.
- Workout and proposal lookups go through the user's plans; time-off deletion through the user's active plan. Missing and foreign IDs get the same empty 404.
- Future watts come from `TrainingPlan#ftp_watts_for_planning`; completed snapshots keep their recorded FTP. Pure `Training` and `Planning` calculations never read request-global state.
- The session-backed preview draft is bound to its creator and cleared on account change; confirmation checks the owner.
- `IntervalsIcu::SyncCalendar` receives the rider's profile, plan and owner-scoped sync records. `IntervalsIcuSync.user_id` attributes detached records after a workout is deleted, so cleanup can't touch another rider's records.

Database foreign keys require ownership of profiles, plans and sync records, with per-user indexes for one profile and one active plan. Request specs cover a two-rider matrix. See [DATA_MODEL.md](DATA_MODEL.md#ownership-schema) and [REQUIREMENTS.md](REQUIREMENTS.md#16-independent-riders).

## Plan creation and calendar

- `TrainingPlansController` stores valid preview inputs in the Rails session, redirects to a refreshable GET preview, restores them on Back to edit and consumes them on confirmation. Preview never persists a plan.
- `Planning::PlanConfiguration` validates inputs and owns the end date (`ends_on`), also served read-only by the `end_date` endpoint. `Planning::Availability` holds weekly slots using ISO weekdays (Monday = 1).
- `Planning::PlanBuilder#preview` builds phases, prescriptions, recovery and taper treatment, forecast metrics and load warnings in memory, delegating to `PhaseAllocator` and `IntervalSelector`. `PreviewPresenter` formats it.
- `Planning::RecoverySchedule` aligns recoveries near phase transitions and supplies the same flags to previews, the calendar and load context (`for_plan` builds it for a saved plan, including for `Workouts::Mover`).
- Tapers get separate early and final load budgets against a comparable peak week, keeping the event and opener; saved main-set factors and ceilings survive later generation.
- `Planning::TimeOffTimeline` is the single definition of blocked dates (break plus return ramp), overlapped weeks, the latest completed break and the ramp stage on a date.
- `AvailabilityTemplate.for_date` is the single availability lookup: a one-week override wins, then the latest `effective_from`, then the newest record.
- `Planning::PlanCreator#create!` rebuilds the same preview and persists plan, phases, template, optional event and outlines in one transaction, then materialises the horizon.
- `Planning::WorkoutBuilder#call` structures executable outlines in `date..date+13` (default today) under the plan lock. It applies the latest accepted bias once through `Training::Progression`, keeps reduced-load ceilings, and saves level, steps and owner-FTP metrics together. It runs after creation, on calendar load and after re-prescription, and never changes structured, completed or missed records. `build_for_completion!` structures a single due or overdue outline the same way when it's opened or completed.
- `Planning::WeeklyLoadCap` and `LoadReduction` apply the ordered §27 reductions: levels (highest-load first), lower-load variations, lower targets within bands, compatible subtype for broad Intervals, then short main sets with easy filler. Partial, recovery, taper, time-off and re-entry weeks are never reference weeks. Normal duration, specific subtype intent and the chosen endurance profile stay fixed; if nothing fits, a non-blocking warning is shown. Stored automatic load references stop one-off manual increases raising the next hard week's baseline.
- `Planning::CalendarPresenter` groups workouts by date and derives week summaries, which also feed the weekly TSS chart. With no plan it shows four weeks starting last week.

Forecasts always pass an explicit variation; only initial endurance materialisation picks a random profile (WKO-009). There is no FTP-test scheduling.

### Discipline

`Planning::Rules::INTERVAL_CYCLES` and `IntervalSelector` choose non-event broad Intervals by goal and phase only, and `LoadReduction` follows the same cycles. Event discipline affects event Build/Speciality selection only; event Base is generic and specific weekly subtypes bypass selection. `Workouts::Generator` carries discipline as context without changing steps.

Non-event plans store the `Planning::Rules::NON_EVENT_DISCIPLINE` Road default to satisfy the enum; it's never a training input. `ExistingPlanConfiguration` reads saved values, so legacy plan/event mismatches are left as they are. Inactive event and duration inputs survive editing without being validated. See [DATA_MODEL.md](DATA_MODEL.md#trainingplan).

The `plan-configuration` Stimulus controller fetches the end date, disables inactive fieldsets and appends their values to the draft through the native `formdata` event. The single `plan_length` input maps onto the preset/custom modes.

## Workout generation and editing

- `Workouts::Generator` composes warm-up, main or aerobic set, cool-down and exact-duration fitting into a `WorkoutDefinition` of expanded `StepDefinition`s. `OpenerGenerator` builds the 30–45 minute activation structure.
- `Workouts::Variations` holds variation keys, the deterministic Same rotation and initial random endurance selection. Nothing calls an LLM or external API.
- `Metrics::WorkoutCalculator` derives one-second power, NP, IF, TSS and work from canonical steps and FTP. `Workouts::ProfileBuilder` supplies graph data; `CalendarHelper` renders inline SVG graphs and summarises repeated main sets and watt ranges (owner FTP when planned, frozen snapshots when completed). Summaries are presentation, never inputs.
- `Workouts::ManualEditor` handles Same, Easier, Harder, Shorter, Longer, Change and accepted progression edits, replacing steps and metrics in a transaction. `preview` runs the same path without writing, so comparisons match what acceptance saves.
- A material Change creates an optional proposal (`Planning::MaterialChangeProposal`); on acceptance `MaterialChangeReplanner` keeps the changed workout fixed and re-prescribes the following 14 days.
- `Workouts::Creator` adds a structured workout to an empty date (regular workouts start at level 1). `Workouts::Copier` copies a planned structured workout, recalculating metrics at current FTP.

**Easier/Harder.** Pure `Workouts::DirectionalAdjustment` searches replacements and keeps the first whose actual and displayed whole-number TSS both move the requested way (display rounding matches database precision). Ladder subtypes (`Training::Rules::LADDERS.key?`) try the nearest levels first, then current-level variations, preferring the saved one. Endurance and Recovery search profiles only and have no level (`fit_aerobic` returns `progression_level: nil`). `ManualEditor` applies the result under the plan lock; at the limit nothing is written and the rider sees a message. See the [manual adjustment sequence](diagrams/sequence-cyclefar-directional-adjustment.puml).

**Destinations.** `Workouts::DestinationValidator` is shared by Add, Copy, Move and missed Move: an empty date inside the plan and a phase, outside time off and not the event date. It runs under the plan lock; Move excludes its own source.

**Moves.** `Workouts::Mover` handles ordinary and missed Move under the plan lock.

- Same-phase moves of up to seven days keep steps, variation and manual levels if the recovery/return context still matches.
- Otherwise the workout regenerates for its destination date, phase and bias, keeping kind, subtype, intent and duration, with destination ceilings. `Planning::PhaseProgression` shares the phase-level calculation with `PlanBuilder`.
- Structures stay structured outside the horizon; distant outlines keep forecasts and an unbiased baseline.
- Move rejects non-planned sources and archived plans.

**Load review.** `Planning::WeeklyLoadReview` reads fixed workouts and outline forecasts without changing them, using `LoadContext` for reference-week rules. A regenerated move is reduced through `WeeklyLoadCap`; short preserved moves are rider choices and may exceed the cap with a warning. `weeks_above_target` returns the affected weeks to `HomeController`, which renders the `home/_load_guidance` panel with links to each week (`#calendar-week-<ISO date>`) and a prefilled availability form.

**Removal.** `Workouts::Remover` deletes a planned or missed workout and its steps under the plan lock, from any date. It doesn't replan or call the API; the sync identity is kept for the next manual sync, and affected proposals become stale. Calendar loads don't refill the date.

## Completion, adaptations and schedule changes

- **Completion.** `Adaptations::CompletionRecorder` saves feedback and immutable FTP, target and metric snapshots in a transaction, then saves any proposal from `FeedbackEvaluator`. It accepts structured regular workouts and openers, and structures a due or overdue outline in the same transaction. Openers record RPE and quality but drive no adaptation (no opener RPE band is defined).
- **Ride files (FBK-004).** `Workouts::RideFileAttacher` decodes the FIT file with the in-house `Fit::Reader` outside the plan lock, then under the lock calculates ridden metrics with `Metrics::RideCalculator` at the frozen completion FTP and creates or replaces the `WorkoutActivity` and its file. `RideFileRemover` deletes both. Ridden and planned NP share `Metrics::NormalizedPower`. Ridden metrics feed nothing else.
- **Feedback.** `Adaptations::FeedbackEvaluator` reads persisted feedback and upcoming workouts (it is not pure).
  - It targets regular structured workouts from today through day 13: same subtype first, then the Tempo/Sweet Spot/Threshold or VO2/Over-under family, then broad Intervals if the source was broad Intervals.
  - Struggled feedback also reduces nearby broad Intervals; failed feedback can reduce any nearby intensity session ("nearby" means within two days after the source, inside the horizon).
  - High-RPE, struggled or failed easy rides narrow the next same-subtype ride's ranges to their lower ends.
  - No-op or load-increasing changes are dropped. Late feedback is ignored once the next scheduled workout is completed (FBK-003).
  - Repeated patterns use the last three completed rides with feedback in the comparable family (§30), each judged against its own RPE band, and propose a global bias change.
- **Comparison.** `Adaptations::ProposalComparison` validates the full source/target set through the plan and calculates current and proposed prescriptions at the plan's FTP, plus the bias change. `FeedbackLoadLimiter` applies the same ceilings and weekly cap as horizon generation, so preview and acceptance match. Targets moved outside the horizon are rejected. Invalid payloads show "unavailable" with Reject only.
- **Acceptance.** `Adaptations::ProposalApplier` locks the plan then the proposal, revalidates, applies changes through `ManualEditor`, saves the clamped `intensity_bias` (−2..+2) and destroys the proposal, all in one transaction. Reject only destroys it.
- **Freshness.** `ProposalCreator` captures context under the plan lock. `ProposalFreshness` checks expiry (`Time.current >= expires_at`), active status and a digest of the source and targets, affected and reference load weeks, availability, time off and return ramps, phases and progression state (material replans add their block, event and pre-break levels). FTP and metrics are excluded, so an FTP change doesn't invalidate proposals. Stale, expired or unverifiable proposals can only be dismissed. Edits, moves, completion, missed resolution, Add/Copy and archive take the same plan lock. Per-family bias (§32) is not implemented.
- **Missed workouts.** `Planning::MissedWorkoutResolver` supports `leave_unchanged`, `move` and `replan`, for past or current workouts only. Replan keeps the missed record and re-prescribes today through day 13 (bounded by plan end).
- **Availability.** `Planning::AvailabilityChanger` versions templates and re-prescribes the affected one-week or from-date range. `AvailabilityChangesController#new` takes an optional `effective_from` (default today, clamped to the plan) and prefills slots through `Planning::AvailabilityForWeek`, which reads templates only, not adjusted workouts.
- **Time off.** `Planning::TimeOffPlanner` adds and removes periods and re-prescribes from the period start.
- **Re-prescription.** All four replanners use `FuturePrescriber.replace_with_templates!`, which resolves the effective availability template per date, so one-week overrides and later changes keep their own slots. `FuturePrescriber` replaces future planned prescriptions under the plan lock, accounting for time off and return ramps, leaving completed and missed records alone, then materialises the horizon. It keeps the unbiased baseline apart from post-break ceilings so bias never stacks.
- **Returns.** `Planning::ReturnRamp` computes stages, duration and power limits and progression from the reduced post-ramp level. `PreBreakProgression` uses the latest comparable planned or completed regular session (not a historical maximum); freshness uses the same calculation. `Workouts::TargetBandLimiter` constrains main targets and caps every step endpoint. Saved return limits survive profile sampling and materialisation.
- **FTP.** `Settings::Update` and `Settings::FtpHistory` (owner-scoped edits and deletions, current FTP from the newest reading) both go through `Settings::FtpMutation`, which takes the owner advisory lock before row locks. `Planning::FtpRecalculator` refreshes future structured metrics without touching steps or completed snapshots. After commit, a changed current FTP calls `IntervalsIcu::RefreshSyncedWorkouts`; a remote failure never rolls back the FTP change.

## Integration

- `IntervalsIcu::WorkoutSerializer` turns canonical steps into a flat workout description plus current-FTP metadata. `IntervalsIcu::Client` isolates Basic auth, JSON, timeouts and one retry.
- `IntervalsIcu::EligibleWorkouts` defines eligibility for both sync and FTP refresh.
- `IntervalsIcu::SyncCalendar` saves identities before upload, upserts every eligible workout, confirms the response with `ConfirmedUpserts`, then deletes the rider's tracked events outside the set. `RefreshSyncedWorkouts` upserts only confirmed exports and deletes nothing. `ConfirmedUpserts` rechecks eligibility and linkage after HTTP, so detached identities are never reattached.
- `Planning::PlanRemover` calls `IntervalsIcu::RemovePlanEvents` before deleting or archiving; remote failure keeps the plan active.
- `IntervalsIcu::Synchronization` takes an owner-scoped PostgreSQL session advisory lock around sync, refresh and removal without holding transactions open across HTTP.

See [INTERVALS_ICU.md](INTERVALS_ICU.md) for the request contract. Specs stub HTTP.

## Routes and UI boundaries

The authoritative routes are in [`config/routes.rb`](../config/routes.rb):

```ruby
resource :session
resource :registration, only: [:new, :create]
resources :passwords, param: :token
root "home#index"
resource :settings, only: [:show, :update]
resources :ftp_readings, only: [:edit, :update, :destroy]
resource :training_plan, only: [:new, :create, :destroy] do
  get :preview
  post :preview, action: :prepare_preview
end
resources :planned_workouts, only: [:new, :create, :show, :destroy] do
  member do
    post :shuffle
    post :change
    post :move
    post :copy
    post :complete
    post :miss
  end
  resource :ride_file, only: [:create, :destroy]
end
resources :adaptation_proposals, only: [] do
  member do
    post :accept
    delete :reject
  end
end
resource :availability_change, only: [:new, :create]
resources :time_off_periods, only: [:new, :create, :destroy]
resource :intervals_icu_sync, only: :create
```

`/up` is the Rails health endpoint. Workout detail is a full page with inline forms and redirects, not a Turbo Frame modal; UX.md's modal recommendations are not implemented.

## Persistence, dates and invariants

- Multi-record mutations use transactions. Domain operations are explicit services, not model callbacks.
- Database constraints enforce one profile and one active plan per user, one workout per plan and date, valid enums and key numeric bounds.
- Model guards and PostgreSQL triggers protect completed workouts, steps and feedback, even against direct SQL. Another trigger allows `WorkoutActivity` only on completed workouts and forbids moving it; it can be replaced or removed. The schema dump is `db/structure.sql`.
- Scheduling uses `date` and `Date.current` in the London time zone; weeks start Monday. Exported events use local midnight.
- Percentage steps are canonical; watts are derived for future workouts and frozen at completion.
- `TrainingPlan#engine_version` records `v1` as metadata only; engine classes live directly under `Training` and `Planning`.
- `PlannedWorkout#generation_context` keeps unbiased baselines, automatic load and level references and ceilings apart from one-off edits.
- API keys use Active Record Encryption and filtered parameters. Passwords use `has_secure_password`; database sessions are identified by signed, permanent, HttpOnly, SameSite=Lax cookies. Client errors are generic, never echoing external responses or secrets.

## Deployment

The app is live at `cyclefar.com`, deployed with Kamal (`config/deploy.yml`). [Terraform](../infra/README.md) or [CloudFormation](../infra/cloudformation/README.md) provisions one EC2 server, private RDS and optional Route 53 DNS; use one per environment. Provisioning doesn't deploy the app.

- Production reads `DB_HOST`, `DB_PORT`, `DB_USERNAME` and `DB_PASSWORD`. Rails uses primary, cache, queue and cable databases.
- Solid Cache, Queue and Cable run on PostgreSQL. `SOLID_QUEUE_IN_PUMA=true` runs the queue supervisor inside Puma for password-reset mail and ride-file purges. Operator provisioning mails synchronously. The only recurring job is queue housekeeping.
- Active Storage uses local disk at `/rails/storage` on the `cycle_far_storage` Kamal volume. The deployment doesn't back it up, and database backups don't include it.

## Architecture diagrams

PlantUML sources describe the application, not the AWS infrastructure. See the [diagram guide](diagrams/README.md) for the full list, scope and rendering.
