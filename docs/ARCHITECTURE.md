# CycleFar Application Architecture

## Application identity

The Rails application is **CycleFar**. Use `cycle_far` as the project identifier and `CycleFar` as the application module. This is UI/application identity only; domain services and persistence should use generic training-domain names.

## Architecture goals

1. Keep Rails conventional.
2. Keep training logic out of controllers/models where possible.
3. Make plan/workout generation deterministic and exhaustively testable.
4. Keep external integrations behind adapters.
5. Preserve a clean seam for future multi-user support and AI assistance.

## Rails application style

Use standard Rails MVC with a small service/domain layer.

Recommended folders in addition to normal Rails structure:

```text
app/
  controllers/
  models/
  views/
  javascript/controllers/
  services/
    planning/
    workouts/
    metrics/
    adaptations/
    intervals_icu/
  queries/
  presenters/
```

Do not introduce a repository layer, command bus, event sourcing, GraphQL or a front-end SPA for V1.

## Key domain services

### Planning::PlanBuilder

Input: validated plan configuration value object/hash.

Responsibilities:

- calculate plan dates;
- create phase layout;
- insert recovery weeks where configured;
- create/version the initial availability template;
- create high-level daily prescriptions;
- create target event;
- place taper/opener;
- place FTP tests;
- generate structures for the first 14 days;
- calculate weekly load;
- enforce load-growth constraints;
- return a preview representation or persist via an explicit mode/collaborator.

Important: preview and create must use the same planning logic. Do not implement separate algorithms that can drift.

A good shape is:

```ruby
Planning::PlanBuilder.new(configuration).preview
Planning::PlanBuilder.new(configuration).create!
```

where `preview` returns immutable plain data and `create!` persists the same computed plan inside a transaction.

### Planning::PhaseAllocator

Deterministically calculates Base/Build/Speciality/Taper date ranges from:

- total plan duration;
- include-base flag;
- event/non-event;
- event characteristics where available.

### Planning::PrescriptionBuilder

Creates high-level `PlannedWorkout` records from phase + date + active availability slot.

For broad `Intervals`, delegates subtype selection to `Planning::IntervalSelector`.

### Planning::IntervalSelector

Chooses Tempo/Sweet Spot/Threshold/VO2/Over-Under for a broad interval day using:

- goal;
- discipline;
- phase;
- deterministic rotation/index;
- progression state;
- recent feedback state.

No randomness. If variation is desired, use a deterministic `variation_key` sequence.

### Planning::HorizonMaterializer

Ensures all eligible workouts inside `Date.current..Date.current+13` are structured.

Call it:

- after plan creation;
- on calendar load through an idempotent service (acceptable for local V1);
- after FTP/schedule/time-off changes when needed.

Do not regenerate already structured workouts unless an explicit action requires it.

Future production deployment can move routine horizon materialisation to a scheduled job without changing domain logic.

### Workouts::Generator

Input:

- subtype;
- duration;
- progression level;
- phase;
- goal/discipline context;
- variation key;
- modifier (`normal`, `easier`, `harder`);

Output: a `WorkoutDefinition` value object containing:

- descriptive name;
- purpose;
- ordered canonical step definitions;
- main-set summary;
- progression metadata.

The generator never queries the web, calls an LLM or reads Intervals.icu.

### Workouts::ExactDurationFitter

Ensures generated workout steps sum exactly to requested duration.

Rules:

- preserve the main training stimulus first;
- adjust easy warm-up/cool-down/endurance filler within defined bounds;
- if the intended main set cannot safely fit, select the next lower progression level;
- never silently exceed the requested duration except when the rider explicitly chooses Longer.

### Metrics::WorkoutCalculator

Pure service over canonical steps + FTP.

Returns:

- average power estimate;
- estimated Normalized Power;
- IF;
- TSS;
- work kJ.

See `TRAINING_ENGINE.md` for formulas.

### Workouts::ProfileBuilder

Turns canonical steps into compact graph data.

- Use percentage of FTP as the y value so the shape is stable across FTP changes.
- Calendar mini graph: SVG generated server-side or lightweight Stimulus/SVG rendering.
- Detail graph: larger version from the same data.
- Do not add a charting framework unless plain SVG becomes genuinely burdensome.

### Workouts::Shuffler

Handles `same`, `easier`, `harder`, `shorter`, `longer`.

- `same`: next deterministic variation at similar load;
- `easier/harder`: progression adjustment for this workout only;
- duration changes: ±15 minutes, minimum 30 minutes.

### Adaptations::FeedbackEvaluator

Pure rules engine that decides whether feedback warrants a proposal.

Input:

- completed workout + feedback;
- recent comparable feedback;
- current progression state;
- upcoming prescriptions.

Output:

- no proposal; or
- an `AdaptationProposal` payload.

### Adaptations::ProposalApplier

Applies an accepted proposal atomically in a database transaction.

Never apply adaptation merely because feedback was submitted.

### Planning::MissedWorkoutResolver

Modes:

- `leave_unchanged`
- `move`
- `replan`

For replan, only rewrite the near-term block required to restore sensible sequencing.

### Planning::AvailabilityChanger

Creates a new versioned availability template for:

- one week; or
- from date onward.

Then re-prescribes affected future dates, preserving completed workouts.

### Planning::TimeOffPlanner

Adds time off, removes/conflicts future workouts, and reconstructs affected schedule.

Illness/recovery may add a deterministic re-entry load/intensity ramp over user-selected days.

### IntervalsIcu::Client

HTTP wrapper only.

Responsibilities:

- authentication;
- request/response handling;
- timeouts;
- JSON parsing;
- mapping API errors to application-specific errors.

Do not put domain decisions here.

### IntervalsIcu::WorkoutSerializer

Turns canonical steps into valid Intervals.icu workout-builder text.

### IntervalsIcu::SyncNextTwo

Finds the next two eligible structured planned workouts and upserts exactly those app-owned events, updating/deleting prior app-owned sync records as necessary.

## Controllers

Keep controllers orchestration-only. Suggested resources/actions:

```text
root -> calendar#index

resource :settings, only: [:show, :update]

resource :training_plan, only: [:new, :create, :destroy] do
  post :preview
  get  :preview_result # only if needed by chosen form flow
end

resource :calendar, only: [:show]

resources :planned_workouts, only: [:show, :update] do
  member do
    post :shuffle
    post :complete
    post :miss
    post :move
    post :change
  end
end

resources :adaptation_proposals, only: [] do
  member do
    post :accept
    delete :reject
  end
end

resources :time_off_periods, only: [:new, :create, :destroy]
resource  :availability_change, only: [:new, :create]
resource  :intervals_icu_sync, only: [:create]
```

Exact route names may differ, but avoid giant controllers with branching action parameters when distinct operations deserve explicit endpoints.

## Turbo/Stimulus usage

Use Turbo Frames/Streams for:

- workout detail modal;
- shuffle/change previews;
- completion feedback and adaptation proposal transition;
- calendar card/weekly total replacement after edits;
- Intervals.icu sync status.

Use Stimulus for:

- conditional plan configuration fields;
- duration increment controls;
- modal behaviour if necessary;
- workout profile rendering if not server-rendered SVG;
- confirmation UI.

Do not use Stimulus as a client-side domain engine. All training rules live in Ruby.

## Transactions and invariants

Use transactions for:

- plan confirmation/creation;
- accepted adaptation;
- availability replan;
- time-off replan;
- archiving a plan;
- moving/change operations that affect multiple workouts.

Important invariants:

- max one active plan;
- max one cycling workout per plan/date;
- completed workouts are never mutated by plan operations;
- detailed step duration equals workout duration;
- every structured normal/opener workout has at least one step;
- every future target is percentage-based internally;
- external sync operations never delete non-app-owned Intervals.icu events.

## Date handling

This product is date-centric, not time-centric.

- Persist scheduling with `date`, not `datetime`, whenever possible.
- Use `Date.current` consistently.
- Weeks begin Monday.
- Intervals.icu serialization may require a local datetime; serialize date-only workout calendar events at local midnight without adding workout-time semantics to the domain.

## Error handling

User-visible errors should be useful and recoverable.

Examples:

- invalid plan configuration -> field errors;
- impossible workout fit -> generator steps down progression and records why; only raise if no safe 30-minute structure exists;
- Intervals.icu auth failure -> show `API key rejected` without exposing key;
- HTTP timeout -> show sync failed; leave local plan untouched;
- stale adaptation proposal -> refuse apply and regenerate a proposal rather than applying stale changes.

## Logging

Log high-level generation decisions in development for debugging, e.g.:

```text
plan_engine goal=increase_ftp phase=build date=2026-10-06 intent=intervals subtype=threshold level=3
```

Never log secrets. Avoid logging full Intervals.icu request headers.

## Versioning training rules

Persist `TrainingPlan#engine_version`.

All initial rules are `v1`. This allows later training-engine revisions without silently reinterpreting historical plans.

A future AI layer should call the deterministic engine or propose changes to it; it should not replace the canonical workout/plan model.
