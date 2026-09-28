# CycleFar — Rails Data Model

The training model was reviewed against models, migrations and `db/structure.sql` on 2026-09-28. Rails authentication and required profile, plan and sync ownership are reflected in the checked-in SQL schema dump alongside completed-history triggers. Enums use string values. JSONB holds progression state, proposal payloads and immutable completion snapshots.

This describes the implemented persistence shape; [REVIEW.md](REVIEW.md) records service behaviour that still falls short of the requirements.

## User and Session

Rails-generated authentication records are separate from the training domain. `User` has a unique, normalized `email_address`, a `password_digest` managed by `has_secure_password`, timestamps and many sessions. `Session` belongs to a user and stores `ip_address`, `user_agent` and timestamps. The `users` and `sessions` migrations add the required columns, unique email index and session foreign key.

`RiderProfile`, `TrainingPlan` and `IntervalsIcuSync` now have required `user_id` foreign keys. Plan children inherit ownership through their plan; FTP readings inherit it through their profile. Training controller record lookups, preview drafts and sync reconciliation are owner-scoped, and FTP-based services use the plan's owner. Public registration creates an ordinary `User` and `Session`; it adds no registration table.

## RiderProfile

One profile per `User`, enforced by a required foreign key and unique index. The singleton `id = 1` rule and `RiderProfile.current` API were removed. First Settings save builds the signed-in user's profile when needed.

Fields:

- `ftp_watts: integer, null: false`
- `intervals_icu_api_key: string` — encrypted with Active Record Encryption
- `user_id: bigint, null: false` — unique foreign key to `User`
- timestamps

Validations:

- FTP > 0

Public registration, controlled account provisioning and an automated two-rider isolation matrix are implemented locally. Deployment with additional riders remains pending the release prerequisites in [TWO_RIDER_RELEASE_GATE.md](TWO_RIDER_RELEASE_GATE.md); the operator provisioning task remains disabled by default.

## FtpReading

Lightweight history; no V1 UI. `belongs_to :rider_profile` via required `rider_profile_id`.

Fields:

- `ftp_watts: integer, null: false`
- `effective_on: date, null: false`
- timestamps

Create one whenever Settings FTP changes to a new value.

## TrainingPlan

Fields:

- `user_id: bigint, null: false` — foreign key to `User`
- `status: enum` — `active`, `archived`
- `goal: enum` — `general_fitness`, `increase_ftp`, `improve_endurance`, `improve_climbing`, `event`
- `discipline: enum` — `road`, `gravel`, `mtb`, `ultra_endurance`
- `starts_on: date`
- `ends_on: date`
- `include_base: boolean`
- `progression_mode: enum` — `continuous`, `hard_recovery_cycle`
- `hard_weeks_before_recovery: integer, nullable`
- `initial_ftp_watts: integer`
- `progression_state: jsonb, default: {}` — currently stores the accepted global `intensity_bias` (-2..+2); generation does not yet consume it (see REVIEW.md)
- `engine_version: string` — e.g. `v1`
- timestamps

Constraints:

- partial unique index on `user_id` ensuring at most one `active` plan per user.

Do not destroy archived plans that have completed workouts. The current archive action removes planned records and retains completed and missed records; a plan without completed workouts is deleted.

## TargetEvent

`belongs_to :training_plan`

Fields:

- `name: string, null: false`
- `event_on: date, null: false`
- `discipline: enum, null: false`
- `distance_km: decimal, nullable`
- `elevation_m: integer, nullable`
- `expected_duration_minutes: integer, nullable`
- timestamps

A plan has zero or one target event.

## PlanPhase

`belongs_to :training_plan`

Fields:

- `kind: enum` — `base`, `build`, `speciality`, `taper`
- `starts_on: date`
- `ends_on: date`
- `position: integer`
- timestamps

Validation: non-overlapping, contiguous inside plan dates (except plan dates used solely for an event if represented separately).

## AvailabilityTemplate

Versioned repeating weekly schedule.

`belongs_to :training_plan`

Fields:

- `effective_from: date`
- `effective_until: date, nullable`
- `source: enum` — `initial`, `one_week_override`, `from_date_change`
- timestamps

`has_many :availability_slots`

This model supports both one-week changes and changes from a date onward while preserving historical intent.

## AvailabilitySlot

`belongs_to :availability_template`

Fields:

- `weekday: integer` — ISO `Date#cwday`, Monday=1...Sunday=7
- `duration_minutes: integer`
- `intent: enum` — `intervals`, `endurance`, `recovery`, `vo2_max`, `threshold`, `sweet_spot`, `tempo`
- timestamps

Only configured workout days need rows. Missing weekday = rest.

## TimeOffPeriod

`belongs_to :training_plan`

Fields:

- `starts_on: date`
- `ends_on: date`
- `reason: enum` — `holiday`, `illness`, `recovery`, `event`, `other`
- `name: string, nullable`
- `return_ramp_days: integer, nullable`
- timestamps

`return_ramp_days` required for illness/recovery, absent for holiday, event and other reasons.

## PlannedWorkout

This represents both high-level prescriptions and detailed workouts.

`belongs_to :training_plan`
`belongs_to :plan_phase, optional: true`

Fields:

- `scheduled_on: date, null: false`
- `kind: enum` — `workout`, `ftp_test`, `opener`
- `intent: enum` — same broad/specific domain as schedule where applicable
- `subtype: enum, nullable` — `recovery`, `endurance`, `tempo`, `sweet_spot`, `threshold`, `vo2_max`, `over_under`
- `duration_minutes: integer, nullable` — FTP test can be nil/unknown
- `name: string`
- `purpose: string`
- `detail_status: enum` — `outline`, `structured`
- `status: enum` — `planned`, `missed`, `completed`
- `progression_level: integer, nullable`
- `variation_key: string, nullable` — persisted descriptive profile key; Same shuffle rotates deterministically, while initial endurance generation randomly selects a profile (TRAINING_ENGINE.md §15)
- `estimated_np_watts: decimal, nullable`
- `estimated_if: decimal, nullable`
- `estimated_tss: decimal, nullable`
- `estimated_work_kj: decimal, nullable`
- `completed_ftp_watts: integer, nullable`
- `completed_target_snapshot: jsonb, nullable` — watt values/metrics frozen at completion
- `completed_at: datetime, nullable`
- timestamps

Indexes:

- unique `[training_plan_id, scheduled_on]` for cycling workout records in V1 (event/time-off are separate models);
- index scheduled date/status/detail status.

Important:

- Do not store planned target watts as the source of truth. Store percentage targets in steps and derive watts from current FTP.
- On completion, snapshot watts/metrics so later FTP changes do not alter history.
- Active Record guards and PostgreSQL triggers protect completed workouts, steps and feedback against updates/deletes.
- Missed records retain their structure/metrics and occupy their date under the same unique constraint. Current calendar totals include them; see REVIEW.md for the reporting decision still needed.

## WorkoutStep

Canonical workout structure. Store an expanded flat sequence; do not make Intervals.icu text the domain model.

`belongs_to :planned_workout`

Fields:

- `position: integer`
- `kind: enum` — `steady`, `ramp`
- `label: string` — warm-up/main/recovery/cool-down cue
- `duration_seconds: integer`
- `target_low_pct_ftp: decimal`
- `target_high_pct_ftp: decimal`
- for ramp steps:
  - `end_target_low_pct_ftp: decimal, nullable`
  - `end_target_high_pct_ftp: decimal, nullable`
- `group_key: string, nullable` — identify repeated main-set groups for display/summarisation
- `group_iteration: integer, nullable`
- timestamps

Constraints:

- duration > 0;
- all percentages > 0;
- low <= high;
- ramp endpoint fields required only for ramp.

Why flat/expanded steps:

- easy metric calculation;
- easy profile graph generation;
- straightforward exports;
- avoids nested-repeat complexity;
- repeat grouping can still be reconstructed for human summaries.

## WorkoutFeedback

`belongs_to :planned_workout`

Fields:

- `rpe: integer` (1–10)
- `completion_quality: enum` — `as_planned`, `struggled_completed`, `could_not_complete`
- timestamps

One feedback record per completed workout.

## AdaptationProposal

Ephemeral persistence so a proposed multi-workout change can survive a page render without stuffing data in cookies.

`belongs_to :training_plan`

Fields:

- `reason: string`
- `payload: jsonb` — proposed deterministic changes and before/after values
- `expires_at: datetime`
- timestamps

Feedback-proposal payloads contain `changes` (workout ID and proposed progression level), `progression_bias`, and `source_workout_id`. Material Change Workout proposals use a type discriminator plus the source workout and bounded replan dates. Both proposal paths use a seven-day `expires_at`.

On accept: check target/source workouts are still planned/structured, apply atomically, then destroy the proposal. A material-change replan preserves its changed source workout and regenerates only its bounded future block. On reject: destroy the proposal. Expiry, full stale-content checks and before/after values are not yet implemented; see REVIEW.md.

No long-term proposal history is required.

## IntervalsIcuSync

Track only events created by CycleFar.

`belongs_to :planned_workout, optional: true` via nullable `planned_workout_id`. Deleting a workout nullifies this foreign key so the sync record survives for remote cleanup. Model updates cannot reassign its external identity.

Fields:

- `user_id: bigint, null: false` — foreign key to `User`; retained when the workout is deleted
- `external_id: string, null: false` — stable CycleFar-owned ID sent to Intervals.icu (use a `cyclefar-` prefix)
- `intervals_event_id: bigint, nullable`
- `last_synced_at: datetime`
- `payload_digest: string` — detect whether a changed workout needs update
- timestamps

Unique indexes on `external_id` and `planned_workout_id`.

## Derived concepts (do not necessarily persist)

Prefer service/query objects for:

- current 14-day horizon;
- weekly totals;
- awaiting-status state (`planned && scheduled_on < Date.current`);
- power targets in watts;
- calendar month-boundary labels;
- workout graph points.

## Planned Milestone 12 ownership schema and migration contract

This section records the independent-rider ownership design and its implementation. CYF-67–72 delivered the explicit-owner backfill, required ownership constraints, request/service scoping, preview isolation and sync isolation. CYF-73/74 added controlled provisioning and an automated two-rider matrix. Deployment prerequisites remain in [TWO_RIDER_RELEASE_GATE.md](TWO_RIDER_RELEASE_GATE.md). [USR-001–USR-008](REQUIREMENTS.md#16-planned-independent-rider-release) define the full acceptance contract.

| Record | Ownership and constraint |
|---|---|
| `RiderProfile` | Implemented: required `user_id` foreign key and unique index; the `id = 1` check and `RiderProfile.current` have been removed. First Settings save with a valid FTP establishes the user's profile. |
| `FtpReading` | Keep required `rider_profile_id`; owner is the profile's user. |
| `TrainingPlan` | Implemented: required `user_id` foreign key and unique partial index on `user_id` where `status = 'active'` in place of the global active-plan index. Archived plans remain attached to their owner with completed history. |
| Plan children | `TargetEvent`, `PlanPhase`, `AvailabilityTemplate`/`AvailabilitySlot`, `TimeOffPeriod`, `PlannedWorkout`/`WorkoutStep`/`WorkoutFeedback` and `AdaptationProposal` inherit ownership through their plan. |
| `IntervalsIcuSync` | Implemented: required `user_id` foreign key in addition to the nullable `planned_workout_id`; the direct owner survives workout deletion. Unique `external_id` and `planned_workout_id` indexes remain. |

Application associations and validations complement these database constraints. Controller lookups and services must use the authenticated owner's profile and plan even when a foreign record ID is supplied. Pure workout calculations continue to take explicit inputs rather than reading the request context.

The CYF-67/68 migrations preflight each target database, require an explicitly selected existing account for legacy training data, backfill profile, plans and sync rows, then enforce profile/plan `NOT NULL`, foreign keys and per-user uniqueness. CYF-72 derives any remaining linked sync owner from its plan, requires an explicit owner for unassigned detached rows, and enforces sync `NOT NULL` and a user foreign key. They preserve completed snapshots, FTP history, the encrypted API-key value and `cyclefar-` external IDs. The local development authentication-table conflict has been resolved; production preflight and copy rehearsal remain deployment prerequisites. See [the migration runbook](LEGACY_OWNER_MIGRATION.md).

The ownership, scoping, preview and sync code has automated two-rider coverage, but a second rider remains disabled pending target-data rehearsal, live mail verification and Milestone 11 acceptance. The checked-in `db/structure.sql` and the implemented model descriptions above remain authoritative for current behavior.
