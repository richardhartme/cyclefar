# CycleFar Application Architecture

Training architecture reviewed against the repository on 2026-09-24; authentication and ownership additions checked through 2026-09-28. This document maps the implemented application; [REQUIREMENTS.md](REQUIREMENTS.md) and [TRAINING_ENGINE.md](TRAINING_ENGINE.md) define intended behaviour. Known differences are tracked in [REVIEW.md](REVIEW.md).

## Application identity and stack

The application module is `CycleFar`, the project is `cycle_far`, and domain classes remain brand-neutral. The app uses Rails MVC, PostgreSQL, server-rendered ERB, Turbo, Tailwind CSS and plain Ruby domain services. Stimulus is installed, but only the generated example controller is present. Rails-generated authentication gates private application requests. There is no automatic Intervals.icu sync.

## Authentication boundary

`ApplicationController` includes the generated `Authentication` concern. Its default before-action redirects private requests without a valid signed `session_id` cookie to the sign-in page, saving the requested URL in the Rails session for the post-login redirect. `HomeController#index` permits public access and renders a welcome page when signed out; signed-in riders see their calendar. `SessionsController` permits unauthenticated sign-in, creates a database-backed `Session` for a `User`, and destroys it plus the Rails session on sign-out. `Current.session` exposes the current session and user during a request. `PasswordsController` permits unauthenticated reset requests and token-based updates; a successful reset destroys that user's sessions. Sign-in and reset-request actions are rate-limited.

`RegistrationsController` permits a signed-out visitor to create a `User` with a confirmed password, starts a database-backed session, and redirects to the private calendar. It rate-limits account creation and rejects signed-in registration attempts. `Accounts::Provision` and an operator-only task remain available to create a rider with a random password and send a password setup link; the task is disabled until its explicit release flag is set. The application layout identifies the current account and provides sign-out. Production mail uses environment-configured authenticated SMTP, an authorized sender and HTTPS password links; live provider delivery remains to be verified before deployment with additional riders. [ACCOUNT_ACCESS.md](ACCOUNT_ACCESS.md) records the settings and operator procedure. Profile, plan and sync rows require a user; training controller lookups, preview drafts and sync reconciliation are owner-scoped. FTP-based services use the owning plan. Training request specs sign in explicitly and exercise two-user route boundaries.

## Independent-rider boundary

The first independent-rider release uses public registration and controlled provisioning on the existing email/password `User`/`Session` scaffold. Google/social sign-in, coaches, teams and shared plans are outside it. Ownership and isolation code and the automated two-rider matrix are present. Deployment with additional riders remains pending the target database rehearsal and live SMTP verification.

`Current.user` supplies Settings and active-plan controller queries; `RiderProfile.current`, the singleton profile ID and the global active-plan index have been removed. Settings locks the owning user row, and plan creation receives that user explicitly. Workout and adaptation-proposal lookups traverse the user's plans; time-off deletion loads from the user's active plan. Missing and foreign IDs receive the same empty 404 response. FTP-based services and helpers resolve future watts through `TrainingPlan#ftp_watts_for_planning`; completed snapshots use their recorded FTP. Pure `Training::V1` and `Planning::V1` calculations remain independent of request-global state.

The session-backed preview configuration is bound to its authenticated creator or cleared on account change. Confirmation verifies that owner before creating a plan. A sign-out followed by another sign-in in the same browser cannot carry the first rider's draft across accounts.

`IntervalsIcu::SyncNextTwo` receives the signed-in rider's profile, plan and owner-scoped sync relation. A direct `IntervalsIcuSync.user_id` identifies detached records after a workout is deleted, so cleanup cannot consume another rider's stale record. The existing durable `cyclefar-workout-<id>` identity remains stable. API keys and remote operations never cross owner boundaries.

The ownership migrations inventory legacy data and require an explicitly selected existing owner; ambiguous data fails before partial assignment. They backfill profile, plans and linked/detached sync rows, then enforce required profile/plan/sync foreign keys and per-user profile/active-plan indexes. Archived plans and immutable completed records stay attached to their selected owner. [DATA_MODEL.md](DATA_MODEL.md#ownership-schema-and-migration-contract) defines the schema; [REQUIREMENTS.md](REQUIREMENTS.md#16-independent-rider-release) lists the remaining release gate.

Services and presenters currently live under `app/services/`:

```text
app/services/
  planning/       # configuration, previews, persistence, calendar and replanning
    v1/rules.rb  # plan constants and interval-selection cycles
  training/
    v1/rules.rb  # workout constants, power bands and progression ladders
  workouts/      # canonical definitions, generators, editing, adding and copying
  metrics/       # calculations over canonical steps
  adaptations/   # completion and explicit proposal acceptance/rejection
  accounts/      # controlled operator provisioning and password setup delivery
  settings/      # transactional profile and FTP changes
  intervals_icu/ # serializer, HTTP client and next-two reconciliation
```

Avoid repository layers, command buses, event sourcing, GraphQL and front-end SPAs.

## Plan creation and calendar

- `TrainingPlansController` saves valid preview inputs in the Rails session, redirects to a refreshable GET preview, restores them on Back to edit, and consumes the draft on confirmation (CYF-1 and CYF-75). Preview does not persist a plan.
- `Planning::PlanConfiguration` validates setup inputs and `Planning::Availability` represents weekly slots using ISO weekdays (Monday=1).
- `Planning::PlanBuilder#preview` builds in-memory phases, prescriptions, recovery/taper treatment, FTP tests, forecast metrics and load warnings. It delegates phase allocation and subtype selection to `PhaseAllocator` and `IntervalSelector`.
- `Planning::PreviewPresenter` formats that preview for the view.
- `Planning::PlanCreator#create!` rebuilds the same preview, then persists the plan, phases, template, optional target event and outlines in a transaction before materialising the horizon. There is no `PlanBuilder#create!` or separate `PrescriptionBuilder` class.
- `Planning::HorizonMaterializer#call` structures planned executable outlines in `date..date+13`, defaulting to `Date.current`. It runs after creation, on home/calendar load, and after future re-prescription. It leaves existing structured, completed and missed records alone.
- `Planning::CalendarPresenter` loads steps/phases with workouts, groups by date and derives week summaries. With no plan, it renders four Monday–Sunday weeks starting the previous week. The weekly TSS chart uses the same summaries as the calendar, including empty weeks.

Forecast generation always passes an explicit variation. Initial endurance materialisation selects and saves a random profile under WKO-009. Manual Add/Copy can create structured workouts beyond the automatic 14-day horizon.

## Workout generation and editing

`Workouts::Generator` takes subtype, duration, progression level, variation key and phase/goal/discipline context. It composes warm-up, main/aerobic set, cool-down and exact-duration fitting into a `WorkoutDefinition` with expanded `StepDefinition` values. `OpenerGenerator` builds the separate 30–45 minute activation structure.

`Workouts::Variations` centralises descriptive keys, deterministic Same rotation and initial random endurance selection. Explicit variations regenerate deterministically. No generator calls an LLM or an external API.

`Metrics::WorkoutCalculator` calculates representative one-second power, NP, IF, TSS and work from canonical steps plus FTP. `Workouts::ProfileBuilder` supplies percentage-based graph data. `CalendarHelper` renders inline SVG with power-zone colours; the detail graph uses the same canonical data at a larger size.

`Workouts::ManualEditor` handles Same, Easier, Harder, Shorter, Longer, Change and accepted progression adjustments. It replaces steps and metrics transactionally and reports before/after values plus whether the documented material-change thresholds were crossed. A material Change creates a persisted optional proposal through `Planning::MaterialChangeProposal`; `Planning::MaterialChangeReplanner` treats that changed workout as fixed and re-prescribes only the bounded following 14-day block on acceptance. `Workouts::Creator` validates an empty, in-plan, non-event, non-time-off destination and generates a structured workout (regular workouts start at level 1). `Workouts::Copier` copies regular planned structured workouts, retaining canonical steps and recalculating metrics with current FTP.

Move currently lives in `PlannedWorkoutsController` and `Planning::MissedWorkoutResolver`. It validates plan dates/collisions and changes date/phase while retaining structure. Destination regeneration and other remaining requirements are listed in REVIEW.md.

## Completion, adaptations and schedule changes

- `Adaptations::CompletionRecorder` saves feedback and immutable FTP/target/metric snapshots in a transaction, then persists a proposal if `FeedbackEvaluator` returns one. FTP tests have a separate protocol-free completion action.
- `Adaptations::FeedbackEvaluator` reads persisted feedback and upcoming workouts; it is not a pure calculation object. It currently proposes a change to the next structured workout of the same subtype and can propose a global intensity bias.
- `Adaptations::ProposalApplier` applies accepted changes through `ManualEditor`, clamps saved `intensity_bias` to -2..+2, and destroys the proposal in one transaction. Reject only destroys it. Full expiry/staleness checks and consumption of the saved bias are outstanding.
- `Planning::MissedWorkoutResolver` supports `leave_unchanged`, `move` and `replan`. Leave/replan retain a missed record; replan replaces upcoming planned training through `FuturePrescriber`.
- `Planning::AvailabilityChanger` versions weekly templates and re-prescribes affected future dates. `ExistingPlanConfiguration` feeds the existing plan back through the preview engine.
- `Planning::TimeOffPlanner` adds/removes time off and selects the applicable availability template for each future date, respecting one-week overrides and later schedule changes.
- `Planning::FuturePrescriber` replaces future planned prescriptions, accounts for time off and return ramps, preserves completed/missed records and materialises the horizon.
- `Settings::Update` saves rider settings and FTP history transactionally. `Planning::FtpRecalculator` refreshes future structured metrics without changing percentage steps or completed snapshots.

## Integration

`IntervalsIcu::WorkoutSerializer` turns expanded canonical steps into a flat workout-builder description and current-FTP event metadata. `IntervalsIcu::Client` isolates Basic auth, JSON, timeouts and one transient retry. `IntervalsIcu::SyncNextTwo` upserts the next eligible set, deletes stale owned events and persists sync metadata after success. Nullable workout foreign keys retain sync records after local deletion for later remote cleanup.

See [INTERVALS_ICU.md](INTERVALS_ICU.md) for the implemented request contract and reconciliation limits. Remote calls are stubbed in specs.

## Routes and UI boundaries

The authoritative route definitions are in [`config/routes.rb`](../config/routes.rb):

```ruby
resource :session
resources :passwords, param: :token
root "home#index"
resource :settings, only: [:show, :update]
resource :training_plan, only: [:new, :create, :destroy] do
  get :preview
  post :preview, action: :prepare_preview
end
resources :planned_workouts, only: [:new, :create, :show] do
  member do
    post :shuffle
    post :change
    post :move
    post :copy
    post :complete
    post :complete_test
    post :miss
  end
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

`/up` is the Rails health endpoint. Workout detail currently uses a full page with inline forms and redirect responses, not a Turbo Frame modal. Turbo supplies navigation/forms and destructive confirmations. Modal and preview recommendations in UX.md are not evidence that those interactions exist.

## Persistence, dates and invariants

Use transactions for multi-record mutations. Database constraints enforce one profile and at most one active plan per user, one workout per plan/date, valid enums and key numeric bounds. Model guards and PostgreSQL triggers protect completed workouts, steps and feedback, including direct SQL updates/deletes. The SQL schema dump is `db/structure.sql`.

Scheduling uses `date` and `Date.current`; weeks begin Monday. Exported calendar events use local midnight without adding a time-of-day concept. Percentage steps remain canonical; watts are derived for future workouts and frozen at completion. `TrainingPlan#engine_version` records `v1`.

API keys use Active Record Encryption and filtered parameters. Login passwords use `has_secure_password` digests; signed, permanent, HttpOnly, SameSite=Lax cookies identify database sessions. The checked-in `db/structure.sql` includes the generated `users` and `sessions` tables. Client errors use generic messages rather than reflecting external responses or secrets. Domain operations should remain explicit services rather than model callbacks.

## Deployment preparation

The application remains local, with registration and owner-scoped accounts implemented. Separate [Terraform](../infra/README.md) and [CloudFormation](../infra/cloudformation/README.md) alternatives describe one EC2 application server, private RDS and optional Route 53 DNS. No deployed environment is recorded; choose one infrastructure owner per environment.

Production database connections accept `DB_HOST`, `DB_PORT`, `DB_USERNAME` and `DB_PASSWORD`. Rails configures primary/cache/queue/cable databases. `config/deploy.yml` remains a Kamal placeholder; infrastructure provisioning does not deploy the app.

## Architecture diagrams

PlantUML sources describe the logical application, not an already deployed AWS environment:

- [System context](diagrams/cyclefar-system-context.puml)
- [Containers](diagrams/cyclefar-container.puml)
- [Application components](diagrams/cyclefar-component.puml)
- [Plan generation](diagrams/cyclefar-plan-generation-components.puml)
- [Plan changes](diagrams/cyclefar-plan-change-components.puml)
- [Intervals.icu sync](diagrams/cyclefar-intervals-icu-sync-components.puml)

The diagrams were updated for ownership and account access on 2026-09-28. See the [diagram guide](diagrams/README.md) for scope, implementation limitations and rendering requirements.
