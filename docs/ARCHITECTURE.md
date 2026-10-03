# CycleFar Application Architecture

This document maps the implemented application; [REQUIREMENTS.md](REQUIREMENTS.md) and [TRAINING_ENGINE.md](TRAINING_ENGINE.md) define intended behaviour. Known differences are tracked in Jira.

## Application identity and stack

The application module is `CycleFar`, the project is `cycle_far`, and domain classes remain brand-neutral. The repository pins Ruby 4.0.6 and Rails 8.1.4. The app uses Rails MVC, PostgreSQL, server-rendered ERB, Turbo, Tailwind CSS with daisyUI and plain Ruby domain services. JavaScript uses import maps. Stimulus is installed, but only the generated example controller is present. Rails-generated authentication gates private application requests. There is no automatic Intervals.icu sync.

## Authentication boundary

`ApplicationController` includes the generated `Authentication` concern. Its default before-action redirects private requests without a valid signed `session_id` cookie to the sign-in page, saving the requested URL in the Rails session for the post-login redirect. `HomeController#index` permits public access and renders a welcome page when signed out; signed-in riders see their calendar. `SessionsController` permits unauthenticated sign-in, creates a database-backed `Session` for a `User`, and destroys it plus the Rails session on sign-out. `Current.session` exposes the current session and user during a request. `PasswordsController` permits unauthenticated reset requests and token-based updates; a successful reset destroys that user's sessions. Sign-in and reset-request actions are rate-limited.

`RegistrationsController` permits a signed-out visitor to create a `User` with a confirmed password, starts a database-backed session, and redirects to the private calendar. It rate-limits account creation and rejects signed-in registration attempts. `Accounts::Provision` and an operator-only task remain available to create a rider with a random password and send a password setup link; the task is disabled until its explicit release flag is set. The application layout identifies the current account and provides sign-out. Production mail uses environment-configured authenticated SMTP, an authorized sender and HTTPS password links; live provider delivery remains to be verified before deployment with additional riders. [ACCOUNT_ACCESS.md](ACCOUNT_ACCESS.md) records the settings and operator procedure. Profile, plan and sync rows require a user; training controller lookups, preview drafts and sync reconciliation are owner-scoped. FTP-based services use the owning plan. Training request specs sign in explicitly and exercise two-user route boundaries.

## Independent-rider boundary

The first independent-rider release uses public registration and controlled provisioning on the existing email/password `User`/`Session` scaffold. Google/social sign-in, coaches, teams and shared plans are outside it. Ownership and isolation code and the automated two-rider matrix are present. Live SMTP verification remains open.

`Current.user` supplies Settings and active-plan controller queries; `RiderProfile.current`, the singleton profile ID and the global active-plan index have been removed. Settings locks the owning user row, and plan creation receives that user explicitly. Workout and adaptation-proposal lookups traverse the user's plans; time-off deletion loads from the user's active plan. Missing and foreign IDs receive the same empty 404 response. FTP-based services and helpers resolve future watts through `TrainingPlan#ftp_watts_for_planning`; completed snapshots use their recorded FTP. Pure `Training::V1` and `Planning::V1` calculations remain independent of request-global state.

The session-backed preview configuration is bound to its authenticated creator or cleared on account change. Confirmation verifies that owner before creating a plan. A sign-out followed by another sign-in in the same browser cannot carry the first rider's draft across accounts.

`IntervalsIcu::SyncNextTwo` receives the signed-in rider's profile, plan and owner-scoped sync relation. A direct `IntervalsIcuSync.user_id` identifies detached records after a workout is deleted, so cleanup cannot consume another rider's stale record. The existing durable `cyclefar-workout-<id>` identity remains stable. API keys and remote operations never cross owner boundaries.

The ownership migrations enforce required profile/plan/sync foreign keys and per-user profile/active-plan indexes. Archived plans and immutable completed records stay attached to their owner. [DATA_MODEL.md](DATA_MODEL.md#ownership-schema) defines the schema; [REQUIREMENTS.md](REQUIREMENTS.md#16-independent-rider-release) lists the acceptance criteria.

Services and presenters currently live under `app/services/`:

```text
app/services/
  planning/       # configuration, previews, persistence, calendar and replanning
    v1/          # plan rules, shared load context and weekly load cap
  training/
    v1/          # workout rules, power bands, ladders and pure progression calculation
  workouts/      # canonical definitions, generators, editing, adding and copying
  metrics/       # calculations over canonical steps
  adaptations/   # completion, feedback, comparisons, load limiting and acceptance/rejection
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
- `Planning::HorizonMaterializer#call` structures planned executable outlines in `date..date+13`, defaulting to `Date.current`. Under the owning plan lock, it reads the latest accepted global intensity bias, applies it once through pure `Training::V1::Progression`, preserves reduced-load ceilings, and saves the fitted effective level, canonical steps and owner-FTP metrics atomically. It runs after creation, on home/calendar load, and after future re-prescription. Existing structured, completed and missed records remain unchanged. `materialize_for_completion!` uses the same generation and load-limit path for one planned executable outline due today or earlier, preserving saved prescription context and variation while reading current owner FTP and accepted bias. Opening its detail or submitting completion structures only that source; it does not move the rolling horizon backwards.
- `Planning::V1::WeeklyLoadCap` and `LoadReduction` share the ordered §27 reductions: progression levels (highest-load session first), lower-load variations, lower work targets within existing bands, compatible subtype substitutions for broad Intervals, then valid short main sets with easy filler. Materialisation checks actual sampled endurance load against fixed workouts and outline forecasts, adjusting only newly materialised regular workouts while retaining each selected endurance profile. Partial, recovery, taper, assessment, time-off and re-entry weeks are excluded from comparable references. Normal scheduled duration and specific subtype intent remain fixed; infeasible schedules receive a non-blocking warning after valid reductions are exhausted. Stored generated load references prevent one-off manual increases from raising the next hard week's baseline; legacy rows fall back to their stored metrics.
- `Planning::CalendarPresenter` loads steps/phases with workouts, groups by date and derives week summaries. With no plan, it renders four Monday–Sunday weeks starting the previous week. The weekly TSS chart uses the same summaries as the calendar, including empty weeks.

Forecast generation always passes an explicit variation. Initial endurance materialisation selects and saves a random profile under WKO-009. Manual Add/Copy can create structured workouts beyond the automatic 14-day horizon.

## Workout generation and editing

`Workouts::Generator` takes subtype, duration, progression level, variation key and phase/goal/discipline context. It composes warm-up, main/aerobic set, cool-down and exact-duration fitting into a `WorkoutDefinition` with expanded `StepDefinition` values. `OpenerGenerator` builds the separate 30–45 minute activation structure.

`Workouts::Variations` centralises descriptive keys, deterministic Same rotation and initial random endurance selection. Explicit variations regenerate deterministically. No generator calls an LLM or an external API.

`Metrics::WorkoutCalculator` calculates representative one-second power, NP, IF, TSS and work from canonical steps plus FTP. `Workouts::ProfileBuilder` supplies percentage-based graph data. `CalendarHelper` renders inline SVG with power-zone colours; the detail graph uses the same canonical data at a larger size.

`Workouts::ManualEditor` handles Same, Easier, Harder, Shorter, Longer, Change and accepted progression adjustments. It replaces steps and metrics transactionally and reports before/after values plus whether the documented material-change thresholds were crossed. A material Change creates a persisted optional proposal through `Planning::MaterialChangeProposal`; `Planning::MaterialChangeReplanner` treats that changed workout as fixed and re-prescribes only the bounded following 14-day block on acceptance. `Workouts::Creator` validates an empty, in-plan, non-event, non-time-off destination and generates a structured workout (regular workouts start at level 1). `Workouts::Copier` copies regular planned structured workouts, retaining canonical steps and recalculating metrics with current FTP.

`ManualEditor#preview` returns an in-memory definition and metrics without persistence. `apply!` uses the same path, including explicit variation, level clamping and exact-duration fitting, so feedback comparisons match accepted results when inputs remain unchanged.

`Workouts::DestinationValidator` shares Add, Copy, Move and missed Move destination rules: an empty date within the plan and a phase, outside inclusive time-off periods and away from the target event date. Mutations validate under the owning plan lock before changing workouts or steps; Move alone excludes its source from collision checks. Failures show the same date-specific errors and preserve canonical prescriptions and completed history (CYF-8).

`Workouts::Mover` serves ordinary Move and missed-workout Move under the owning plan lock. Same-phase moves of at most seven days preserve canonical steps, variation and manual levels when recovery/return context remains compatible. A phase boundary, greater distance or changed recovery/return context regenerates at the destination's phase/date and accepted bias, preserving kind, subtype, intent and requested duration. `Planning::V1::PhaseProgression` shares the phase-level calculation with PlanBuilder. Source generation ceilings are replaced with destination recovery/taper/post-break ceilings and fitted/load-limited references. Explicit moves retain subtype/duration during reduced-load periods while respecting their level ceilings; automatic schedule/time-off prescriptions still apply their usual subtype/duration overrides. Structured workouts remain structured outside the horizon; distant outlines keep forecasts only and retain an unbiased baseline for later materialisation. FTP tests remain protocol-free. Move rejects non-planned sources, archived plans, occupied/out-of-plan/unphased destinations, time off and the target event date. Preserved structures refresh metrics with owner FTP; completed history and unrelated workouts remain unchanged.

`Planning::WeeklyLoadReview` reads fixed canonical workouts and outline forecasts without mutating them, using `V1::LoadContext` for comparable-week exclusions and saved automatic load references. Move reduces only its regenerated workout through `V1::WeeklyLoadCap`, retaining subtype and duration, then returns a non-blocking destination warning if the cap remains infeasible. Short preserved moves are fixed rider choices and can exceed the cap with a warning. Calendar requests also review future weeks beyond the horizon, so distant move warnings survive a refresh.

## Completion, adaptations and schedule changes

- `Adaptations::CompletionRecorder` saves feedback and immutable FTP/target/metric snapshots in a transaction, then persists a proposal if `FeedbackEvaluator` returns one. This path accepts planned structured regular workouts and openers, and materialises a due/overdue executable outline in the same completion transaction. Metrics are recalculated from canonical steps at the snapshotted current owner FTP, including late structured workouts outside future FTP recalculation. Openers record RPE/quality but do not drive adaptations because V1 defines no opener RPE band. FTP tests have a separate protocol-free completion action.
- `Adaptations::FeedbackEvaluator` reads persisted feedback and upcoming workouts; it is not a pure calculation object. It selects regular planned structured targets only within today through day 13, preferring the same subtype, then the Tempo/Sweet Spot/Threshold or VO2/Over-under family, then broad Intervals when the source intent was Intervals. Struggled feedback additionally reduces nearby broad Intervals; failed feedback can reduce any nearby intensity session. Nearby means after the source date and within two calendar days, still inside the current horizon. High-RPE, struggled or failed easy feedback narrows the next same-subtype ride's existing percentage ranges to their lower endpoints without assigning intensity levels. No-op or load-increasing reductions are omitted. Late feedback is suppressed if the next scheduled workout after the source has already been completed (FBK-003); other completed history remains fixed. Repeated-pattern detection reads the last three completed workouts of the source subtype and proposes a change to the existing global intensity bias.
- `Adaptations::ProposalComparison` validates the full feedback source/target set through the owning plan, sorts targets by date, and calculates current/proposed prescriptions at that plan's FTP alongside the effective global bias transition. `FeedbackLoadLimiter` shares reduced-load ceilings and comparable-week rules through `Planning::V1::LoadContext` with horizon generation and rechecks the weekly cap against fixed workouts and forecasts. Preview and acceptance use the same bounded prescriptions; acceptance rejects targets moved outside the current horizon. The calendar renders these comparisons read-only; invalid payloads show a generic unavailable message with Reject all and no Accept action. Material-change proposals keep their separate replan controls.
- `Adaptations::ProposalApplier` locks the plan and then the proposal, validates through `ProposalComparison`, applies accepted changes through `ManualEditor`, saves the same clamped `intensity_bias` (-2..+2), and destroys the proposal in one transaction. Reject only destroys it. `ProposalCreator` captures versioned proposal-time context under the plan lock. `ProposalFreshness` enforces expiry (`Time.current >= expires_at`), active-plan status and a digest of the canonical source/targets, affected load weeks and their preceding comparable references, applicable availability, time off/return ramps, phases and progression state. Material replans additionally include their bounded block, target event and pre-break level inputs. All context queries use the proposal's plan; current FTP, derived metrics and timestamps are excluded, so metrics-only FTP recalculation remains valid. Payloads without a verifiable baseline are unavailable. Expired/stale/legacy proposals retain dismissal, but omit acceptance in both calendar and workout controls. Manual edits, moves, completion, missed resolution, Add/Copy and archive now share the plan lock with proposal acceptance, preventing concurrent canonical writes from racing validation (CYF-6). Comparison/apply equivalence assumes unchanged canonical inputs. Future horizon generation consumes the saved bias; per-family/subtype state in TRAINING_ENGINE.md §32 remains unimplemented. CYF-3, CYF-4 and CYF-5 delivered comparisons, bias consumption and bounded comparable-workout selection respectively.
- `Planning::MissedWorkoutResolver` supports `leave_unchanged`, `move` and `replan`. Leave/replan retain a missed record; replan replaces upcoming planned training through `FuturePrescriber` in today through day 13, bounded by plan end. It currently uses the template effective today for the whole block; material-change and time-off replanning instead select the effective template per date.
- `Planning::AvailabilityChanger` versions weekly templates and re-prescribes affected future dates. `ExistingPlanConfiguration` feeds the existing plan back through the preview engine.
- `Planning::TimeOffPlanner` adds/removes time off and selects the applicable availability template for each future date, respecting one-week overrides and later schedule changes.
- `Planning::FuturePrescriber` replaces future planned prescriptions under the plan lock, accounts for time off and return ramps, preserves completed/missed records and materialises the horizon. It retains the unbiased baseline separately from an effective post-break ceiling, avoiding feedback-bias stacking. Availability/time-off mutations and proposal acceptance acquire the plan lock before changing children.
- `Settings::Update` saves rider settings and FTP history transactionally. `Planning::FtpRecalculator` refreshes future structured metrics without changing percentage steps or completed snapshots.

## Integration

`IntervalsIcu::WorkoutSerializer` turns expanded canonical steps into a flat workout-builder description and current-FTP event metadata. `IntervalsIcu::Client` isolates Basic auth, JSON, timeouts and one transient retry. `IntervalsIcu::SyncNextTwo` upserts the next eligible set, deletes stale owned events and persists sync metadata after success. Nullable workout foreign keys retain sync records after local deletion for later remote cleanup.

See [INTERVALS_ICU.md](INTERVALS_ICU.md) for the implemented request contract and reconciliation limits. Remote calls are stubbed in specs.

## Routes and UI boundaries

The authoritative route definitions are in [`config/routes.rb`](../config/routes.rb):

```ruby
resource :session
resource :registration, only: [:new, :create]
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

Scheduling uses `date` and `Date.current` in the configured London time zone; weeks begin Monday. Exported calendar events use local midnight without adding a time-of-day concept. Percentage steps remain canonical; watts are derived for future workouts and frozen at completion. `TrainingPlan#engine_version` records `v1`; `PlannedWorkout#generation_context` retains unbiased baseline levels, automatic load/level references and ceilings separately from one-off edits.

API keys use Active Record Encryption and filtered parameters. Login passwords use `has_secure_password` digests; signed, permanent, HttpOnly, SameSite=Lax cookies identify database sessions. The checked-in `db/structure.sql` includes the generated `users` and `sessions` tables. Client errors use generic messages rather than reflecting external responses or secrets. Domain operations should remain explicit services rather than model callbacks.

## Deployment

The application is live at `cyclefar.com`, deployed with Kamal using `config/deploy.yml`. Separate [Terraform](../infra/README.md) and [CloudFormation](../infra/cloudformation/README.md) alternatives describe one EC2 application server, private RDS and optional Route 53 DNS for that environment. Choose one infrastructure owner per environment.

Production database connections accept `DB_HOST`, `DB_PORT`, `DB_USERNAME` and `DB_PASSWORD`. Rails configures primary/cache/queue/cable databases. `config/deploy.yml` reads the web host, database host and registry user from the deploy shell and declares the runtime secrets; infrastructure provisioning does not deploy the app.

Solid Cache, Solid Queue and Solid Cable use their PostgreSQL databases. Kamal sets `SOLID_QUEUE_IN_PUMA=true`, enabling the Solid Queue supervisor through Puma for queued password-reset delivery. Operator provisioning sends mail synchronously. There are no scheduled training-generation or integration-sync jobs; the recurring configuration contains only queue housekeeping. The container view groups Puma and its supervised worker as one deployment unit rather than implying a separate job server.

## Architecture diagrams

PlantUML sources describe the logical application, not the AWS infrastructure:

- [System context](diagrams/context-cyclefar-system.puml)
- [Containers](diagrams/container-cyclefar.puml)
- [Application components](diagrams/component-cyclefar-application.puml)
- [Plan generation](diagrams/component-cyclefar-plan-generation.puml)
- [Plan changes](diagrams/component-cyclefar-plan-change.puml)
- [Intervals.icu sync](diagrams/component-cyclefar-intervals-icu-sync.puml)

Sequence views show request order and the boundaries between in-memory previews, persistence and accepted changes:

- [Create a plan](diagrams/sequence-cyclefar-plan-creation.puml)
- [Change future training](diagrams/sequence-cyclefar-future-replanning.puml)
- [Feedback proposal](diagrams/sequence-cyclefar-feedback-proposal.puml)
- [Material Change Workout proposal](diagrams/sequence-cyclefar-material-change-proposal.puml)

See the [diagram guide](diagrams/README.md) for scope, implementation limitations and rendering requirements.
