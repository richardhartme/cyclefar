# CycleFar Implementation Plan

This is the original milestone sequence, retained as the implementation and acceptance checklist. Milestones 0–11 were delivered in September 2026, followed by additional features. The 2026-09-24 documentation review reopened milestone 11 for outstanding acceptance gaps; see [STATUS.md](STATUS.md) and [REVIEW.md](REVIEW.md).

Rails authentication was generated on 2026-09-27 after this sequence. The milestone tasks below remain historical; [ARCHITECTURE.md](ARCHITECTURE.md) and [STATUS.md](STATUS.md) describe the current authentication scaffold and integration gaps.

Milestone 12 below is a planned independent-rider release. Milestone 11 remains current until its own acceptance gaps and required gates pass; documenting Milestone 12 does not start or complete it.

Build vertical slices. Do not attempt the adaptive engine, calendar UI and external integration in one pass.

## Milestone 0 — Bootstrap and guardrails

Goal: a clean Rails app with the chosen stack and test harness.

Tasks:

- Create the Rails app as `cycle_far` / `CycleFar` with PostgreSQL and Tailwind.
- Pin Ruby/Rails versions.
- Install/configure RSpec and FactoryBot.
- Add WebMock when Intervals.icu work begins (can be deferred).
- Configure Monday-start calendar helpers as application conventions.
- Add basic CycleFar-branded application layout/nav.
- Establish CI-like local command/script if useful.
- Keep the specification in `docs/` and implementation instructions in repository-root `AGENTS.md`.

Exit criteria:

- app boots;
- DB creates/migrates;
- RSpec runs;
- Zeitwerk check passes.

## Milestone 1 — Settings and core persistence

Goal: establish domain schema and immutable-history foundations before generation logic.

Implement:

- RiderProfile singleton;
- FtpReading;
- TrainingPlan;
- TargetEvent;
- PlanPhase;
- AvailabilityTemplate/Slot;
- PlannedWorkout;
- WorkoutStep;
- WorkoutFeedback;
- TimeOffPeriod;
- AdaptationProposal;
- IntervalsIcuSync schema (can remain unused initially).

Add:

- at-most-one-active-plan DB constraint;
- one-workout-per-plan/date constraint;
- validations/enums;
- Active Record Encryption for API key;
- Settings screen.

Tests:

- model invariants;
- FTP history creation behaviour;
- encrypted API-key handling;
- completed workout immutability support primitives.

Exit criteria:

- Settings saves FTP/API key;
- models and constraints are stable;
- no training generation yet.

## Milestone 2 — Pure workout engine

Goal: prove structured workout generation without calendar/plans.

Implement pure Ruby objects:

- zone/target constants;
- progression ladders;
- warm-up/cool-down builders;
- exact-duration fitter;
- generator for Recovery/Endurance/Tempo/Sweet Spot/Threshold/VO2/Over-under;
- deterministic variation keys;
- descriptive names/purpose metadata;
- metrics calculator;
- profile-data builder.

Use POROs/value objects before Active Record where practical.

Tests:

- exhaustive subtype x level x duration matrix;
- exact-duration property;
- target-range boundaries;
- metrics fixtures;
- variation load tolerance.

Exit criteria:

- a console call can generate a valid 60-minute `Threshold 3x12`-style workout and metrics;
- no controller/UI dependency.

## Milestone 3 — Plan preview engine

Goal: generate a complete plan as in-memory preview data.

Implement:

- plan configuration object/validation;
- phase allocator;
- recovery-week overlay;
- interval subtype selector;
- prescription builder;
- FTP-test placement;
- taper/opener logic;
- weekly load estimator;
- 8% generated hard-week load cap;
- preview presenter.

Build plan configuration form and preview screen.

Do not persist an active plan until confirmation.

Tests:

- goals/disciplines;
- Base on/off;
- continuous vs N+1 recovery cycles;
- 1/3/6-month plans;
- event taper lengths;
- FTP test placement;
- weekly load cap.

Exit criteria:

- rider can fill form and see a coherent plan preview with phase dates and weekly load.

## Milestone 4 — Persist plan + continuous calendar

Goal: confirm preview into a real plan and make the calendar the main application.

Implement:

- transactional plan creation from preview/configuration;
- persist all high-level prescriptions;
- materialise first 14 days into steps;
- root behaviour: no plan CTA vs active calendar;
- continuous Monday–Sunday calendar;
- month-boundary labels;
- phase/recovery visual treatment;
- high-level vs detailed cards;
- weekly totals;
- mini workout profile SVG;
- target-event card;
- FTP-test card.

Tests:

- preview and persisted plan are equivalent;
- automatic generation only structures the 14-day horizon (later Add/Copy actions can explicitly create detail outside it);
- weekly totals;
- continuous calendar renders plan start/end.

Exit criteria:

- usable read-only training calendar exists.

## Milestone 5 — Workout detail and manual editing

Goal: make calendar workouts practical to manage.

Implement Turbo detail modal with:

- full graph;
- step breakdown;
- metrics;
- why-this-workout text.

Implement:

- Shuffle Same;
- Easier;
- Harder;
- Shorter/Longer ±15 min;
- minimum 30 min;
- Change Workout;
- optional replan prompt on material Change;
- Move to empty date.

Tests:

- no individual step editing endpoint exists;
- manual harder/easier does not mutate long-term progression;
- shuffle same preserves type/duration and approximate load;
- duration boundaries;
- moving preserves completed-workout invariants.

Exit criteria:

- rider can reshape individual upcoming training without recreating plan.

## Milestone 6 — Completion, overdue and adaptations

Goal: close the feedback loop.

Implement:

- completed state;
- immutable snapshot;
- RPE 1–10;
- completion quality;
- awaiting-status presentation for past planned workouts;
- FeedbackEvaluator;
- AdaptationProposal preview;
- atomic accept/reject;
- long-term progression bias after repeated accepted feedback;
- late-completion rule.

Tests:

- completed snapshots survive FTP changes and replans;
- every feedback rule;
- proposal does nothing before acceptance;
- accept applies all atomically;
- reject destroys/no-ops;
- 2-of-3 pattern logic;
- late completion condition.

Exit criteria:

- rider feedback can safely alter upcoming training without hidden changes.

## Milestone 7 — Missed workouts and schedule changes

Goal: handle ordinary life interruptions.

Implement missed resolution:

- leave unchanged;
- move;
- replan next 7–14 days.

Implement availability changes:

- one week;
- from date onward;
- versioned availability templates;
- future high-level re-prescription;
- horizon rematerialisation.

Tests:

- no “training debt” stacking;
- one workout/day invariant;
- completed/past unaffected;
- phase/event preserved;
- load cap rechecked.

Exit criteria:

- plan can evolve when weekly schedule changes.

## Milestone 8 — Time off and return to training

Goal: support holiday/illness/recovery periods.

Implement:

- add/remove time-off range;
- reasons;
- no workouts during range;
- Holiday/Other resume logic;
- Illness/Recovery user-selected return ramp;
- re-entry stage generation;
- calendar treatment.

Tests:

- overlapping ranges validation;
- event/taper interactions;
- short and long re-entry ramps;
- no completed workout changes;
- plan end remains fixed.

Exit criteria:

- rider can plan a holiday or illness break and see a coherent revised plan.

## Milestone 9 — FTP lifecycle

Goal: make changing FTP safe and useful.

Implement/finish:

- FTP Test special detail/action;
- Settings update recalculation of future watts/work;
- preserve future percentage structures;
- preserve completed snapshots;
- horizon/weekly summary refresh after FTP change.

Tests:

- old completed targets unchanged;
- new displayed future watts updated;
- Intervals serializer uses current FTP context.

Exit criteria:

- six-month plan can be recalibrated repeatedly without historical corruption.

## Milestone 10 — Intervals.icu sync

Goal: explicit next-two export.

Implement:

- client;
- workout serializer;
- stable external IDs;
- next-two selection;
- bulk upsert/reconciliation;
- sync status UI;
- graceful auth/network errors.

Use stubbed HTTP specs.

Tests:

- valid workout-builder syntax for step types;
- next exactly two;
- repeat sync no duplicates;
- move/replan updates/removes app-owned event;
- unrelated events never touched;
- secret never logged.

Exit criteria:

- `Sync next 2` reliably mirrors the app's next two executable workouts in Intervals.icu.

## Milestone 11 — Polish and hardening

Goal: make V1 pleasant enough for daily local use.

Review:

- calendar performance across 6-month plans;
- accessibility and keyboard navigation;
- modal focus handling;
- destructive confirmations;
- empty/error states;
- plan warnings;
- graph readability;
- seed/demo data;
- database indexes/N+1 queries;
- secret filtering;
- test suite speed.

Run full regression suite and manually exercise all requirements.

## Milestone 12 — Independent riders (planned; not current)

Goal: turn the existing authentication scaffold into private training accounts for independent riders while preserving deterministic training and immutable completed history. One `User` has one profile, at most one active plan and any number of archived plans. Accounts are provisioned or invited; public registration, Google/social sign-in, coaches, shared plans and teams remain outside this release.

Implement in this order, with reviewable changes and the [USR-001–USR-008](REQUIREMENTS.md#16-planned-independent-rider-release) coverage targets:

1. **Contract (CYF-66):** document ownership, migration and user-flow requirements without changing current behavior or milestone status.
2. **Legacy preflight/backfill (CYF-67):** inventory target databases, require an explicitly selected existing owner, preserve completed snapshots, FTP history and linked/detached Intervals.icu external IDs, and rehearse a data-preserving migration with recovery steps. Resolve the known local development users/sessions migration conflict before cutover.
3. **Owner schema (CYF-68):** add a unique required `RiderProfile.user_id`, a required `TrainingPlan.user_id` and a per-user partial active-plan unique index after backfill; retain archived plans and child ownership. Update `db/structure.sql`, factories and seeds.
4. **Request and domain boundaries (CYF-69/70):** scope all controller lookups to `Current.user`; pass owned plan/profile context into services, presenters, FTP recalculation and locks. Make foreign and missing IDs indistinguishable. Keep pure training calculations free of request state.
5. **Draft and sync isolation (CYF-71/72):** bind session preview drafts to their creator. Give `IntervalsIcuSync` a required owner, including detached rows, and reconcile only that rider's next-two events with their own API key while keeping stable external IDs.
6. **Account access (CYF-73):** provide controlled provisioning/invitations, visible identity/sign-out and working password-reset delivery. Do not enable a second rider before owner boundaries pass.
7. **Release gate (CYF-74):** run a two-user matrix across Settings, plan preview/creation/archive, calendar, workouts, feedback, missed resolution, availability/time off, FTP, completed history and Intervals.icu. Exercise foreign IDs, concurrent first profile/plan creation, detached sync cleanup and same-browser account switching.

Exit criteria: required migration rehearsal and two-user coverage pass; `bundle exec rspec`, `bin/rails zeitwerk:check` and configured lint/security checks pass; only then update [STATUS.md](STATUS.md) to complete Milestone 12 and name the next current milestone. Milestone 11 must have completed its own gate before Milestone 12 becomes current.

## Later additions already delivered

- No-plan calendar and full-width weekly TSS chart.
- Retained Missed calendar status (MIS-001).
- Copy and Add Workout (WKO-007/008), plus manual Opener selection.
- Event time-off reason and optional time-off names.
- Saved random endurance profiles (WKO-009) and descriptive variation keys.
- Calendar/profile styling and time-off replanning across availability versions.
- Separate AWS infrastructure templates and production database environment configuration.

These additions are documented in the current requirements and status; they do not introduce new milestone numbers.

## Historical first Codex task

Do not ask Codex to “build the app”. Start with:

> Read `AGENTS.md`, `PRODUCT.md`, `REQUIREMENTS.md`, `DATA_MODEL.md` and `ARCHITECTURE.md`. Bootstrap the Rails app and implement Milestones 0 and 1 only. Add migrations, model constraints/specs, Settings UI and encrypted Intervals.icu API-key storage. Do not implement training generation yet. Run the full test suite and Zeitwerk check before finishing.

Then give subsequent Codex sessions one milestone at a time.
