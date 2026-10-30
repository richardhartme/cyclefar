# CycleFar — Rails Data Model

The implemented persistence shape. [`db/structure.sql`](../db/structure.sql) is authoritative; [REQUIREMENTS.md](REQUIREMENTS.md) defines intended behaviour. Enums use string values. JSONB holds progression state, proposal payloads and completion snapshots.

## User and Session

Rails-generated authentication, separate from the training domain. `User` has a unique, normalized `email_address`, a `has_secure_password` digest and many sessions. `Session` belongs to a user and stores `ip_address` and `user_agent`. Registration creates an ordinary `User` and `Session`; there is no registration table. Ownership of training records is described under [Ownership schema](#ownership-schema).

## RiderProfile

One per `User` (required foreign key and unique index), created on the first Settings save.

Fields:

- `ftp_watts: integer, null: false`
- `intervals_icu_api_key: string` — encrypted with Active Record Encryption
- `user_id: bigint, null: false` — unique foreign key to `User`
- timestamps

Validations:

- FTP > 0

## FtpReading

Editable history shown in Settings. `belongs_to :rider_profile` via required `rider_profile_id`.

Fields:

- `ftp_watts: integer, null: false`
- `effective_on: date, null: false`
- timestamps

A reading dated today is created whenever Settings FTP changes. Riders can edit or delete readings through `Settings::FtpHistory`, which always keeps at least one. `RiderProfile#ftp_watts` caches the latest reading (newest `effective_on`, then highest ID); changes update it and future structured metrics atomically under the owner lock. Completed snapshots never change. A profile/date/ID index serves recency queries.

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
- `progression_state: jsonb, default: {}` — stores the accepted global `intensity_bias` (-2..+2)
- `engine_version: string` — e.g. `v1`
- timestamps

Constraints:

- partial unique index on `user_id` ensuring at most one `active` plan per user.

`discipline` is required. Non-event plans store `road` as an internal default from `Planning::Rules`; it isn't a training input and submitted values are ignored. Event plans store the event discipline on both plan and event. Saved values stay authoritative for replanning (legacy mismatches are not backfilled).

Removing a plan with completed workouts archives it, deleting planned records but keeping completed and missed ones; a plan without completed workouts is deleted.

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
- `kind: enum` — `workout`, `opener`
- `intent: enum` — same broad/specific domain as schedule where applicable
- `subtype: enum, nullable` — `recovery`, `endurance`, `tempo`, `sweet_spot`, `threshold`, `vo2_max`, `over_under`
- `duration_minutes: integer` — required and at least 30 minutes (model and database check)
- `name: string`
- `purpose: string`
- `detail_status: enum` — `outline`, `structured`
- `status: enum` — `planned`, `missed`, `completed`
- `progression_level: integer, nullable` — outline prescription level before materialisation; fitted effective interval level once structured; structured Endurance/Recovery and openers have no level
- `generation_context: jsonb, default: {}` — baseline level, effective generation ceiling and generated load/level reference
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
- Missed records retain their structure/metrics and occupy their date under the same unique constraint. Current calendar totals include them.

### `generation_context`

Generation metadata; canonical steps stay authoritative. It must be a JSON object (model validation and database constraint); empty means "fall back to the current level and metrics". Completed rows are never rewritten.

| Key | Meaning |
|---|---|
| `baseline_level` | Unbiased prescription level, kept when a time-off ceiling uses a previously reached level |
| `maximum_level` | Load or re-entry level ceiling |
| `generated_level`, `generated_tss` | The automatic prescription, used as the load reference. One-off manual edits (including Easier/Harder) leave these alone so they don't escalate later generation; accepted feedback refreshes them |
| `load_adjustments.lower_targets`, `.easy_filler` | §27 reduction choices, reused when the outline is materialised |
| `load_adjustments.main_set_factor` | Taper hard-time factor, kept with its fitted level ceiling; power bands are unchanged |
| `load_adjustments.return_target_band` | Return-stage main power ranges and overall step ceiling |
| `return_ramp_stage` | Return stage (1–4), explaining the prescription |

These choices survive endurance-profile sampling and materialisation. The plan's global `intensity_bias` is applied once when an intensity outline enters the horizon (missing means zero); per-family bias (TRAINING_ENGINE.md §32) is not implemented.

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

## WorkoutActivity

`belongs_to :planned_workout`
`has_one_attached :ride_file`

Ridden metrics from an uploaded FIT file (FBK-004). They sit beside the completed workout's frozen snapshot without changing it.

Fields:

- `started_at: datetime, null: false`
- `elapsed_seconds: integer, null: false`
- `moving_seconds: integer, null: false` — at most `elapsed_seconds`
- `average_power_watts: decimal, nullable`
- `np_watts: decimal, nullable`
- `intensity_factor: decimal, nullable`
- `tss: decimal, nullable`
- `work_kj: decimal, nullable`
- `average_heart_rate_bpm: decimal, nullable`
- timestamps

Constraints:

- unique `planned_workout_id`: one ride per workout;
- power metrics are all present or all absent; metrics are non-negative;
- a PostgreSQL trigger accepts rows only for completed workouts and rejects moving a row to another workout. Completed-child immutability triggers do not apply, so the ride can be replaced or removed.

The FIT file is kept in Active Storage on the local disk service so metrics can be recalculated.

## AdaptationProposal

Ephemeral persistence so a proposed multi-workout change can survive a page render without stuffing data in cookies.

`belongs_to :training_plan`

Fields:

- `reason: string`
- `payload: jsonb` — proposed changes, source identity and optional bias delta; before/after comparisons are derived at read/accept time
- `expires_at: datetime`
- timestamps

Payloads:

- **Feedback** (no `type`, or `type = feedback`): `changes` (workout ID and proposed level, plus `lower_targets: true` for easy rides, which narrow ranges instead of changing level), `progression_bias` and `source_workout_id`.
- **Material Change Workout**: a type discriminator, the source workout and the bounded replan dates.
- **Both**: `freshness`, a version plus SHA-256 digest of the relevant workout, schedule and load inputs at creation. Without it the proposal is unavailable and can only be rejected.

`expires_at` is seven days after creation; a proposal is rejected from that moment. Comparisons are derived in memory from canonical steps at the plan's current FTP; no before/after watts are stored. Any invalid reference makes the whole comparison unavailable.

Accepting a feedback proposal checks expiry, active status and unchanged inputs, then that targets are still planned, structured and inside the 14-day horizon, rechecks load limits, applies everything atomically and destroys the proposal. A material-change replan keeps its changed source and regenerates only its block. Rejecting destroys the proposal. No proposal history is kept.

## IntervalsIcuSync

Track only events created by CycleFar.

`belongs_to :planned_workout, optional: true` via nullable `planned_workout_id`. Deleting a workout nullifies this foreign key so the sync record survives for remote cleanup. Model updates cannot reassign its external identity.

Fields:

- `user_id: bigint, null: false` — foreign key to `User`; retained when the workout is deleted
- `external_id: string, null: false` — stable CycleFar-owned ID sent to Intervals.icu (use a `cyclefar-` prefix)
- `intervals_event_id: bigint, nullable`
- `last_synced_at: datetime`
- `payload_digest: string` — records the last successfully exported payload; current sync still upserts on every call
- timestamps

Unique indexes on `external_id` and `planned_workout_id`.

Identities are saved before upload, so an uncertain result stays attributable; event ID, digest and `last_synced_at` stay null until the upload is confirmed. FTP refresh only touches records with both `intervals_event_id` and `last_synced_at`. See [INTERVALS_ICU.md](INTERVALS_ICU.md#sync-reconciliation) for the full flow.

## Derived concepts (do not necessarily persist)

Prefer service/query objects for:

- current 14-day horizon;
- weekly totals;
- awaiting-status state (`planned && scheduled_on < Date.current`);
- power targets in watts;
- calendar month-boundary labels;
- workout graph points.

## Ownership schema

This section records ownership constraints. [USR-001–USR-008](REQUIREMENTS.md#16-independent-riders) define the full acceptance contract.

| Record | Ownership and constraint |
|---|---|
| `RiderProfile` | Required `user_id` foreign key and unique index. First Settings save with a valid FTP establishes the user's profile. |
| `FtpReading` | Keep required `rider_profile_id`; owner is the profile's user. |
| `TrainingPlan` | Required `user_id` foreign key and unique partial index on `user_id` where `status = 'active'`. Archived plans remain attached to their owner with completed history. |
| Plan children | `TargetEvent`, `PlanPhase`, `AvailabilityTemplate`/`AvailabilitySlot`, `TimeOffPeriod`, `PlannedWorkout`/`WorkoutStep`/`WorkoutFeedback`/`WorkoutActivity` and `AdaptationProposal` inherit ownership through their plan. |
| `IntervalsIcuSync` | Required `user_id` foreign key in addition to the nullable `planned_workout_id`; the direct owner survives workout deletion. Unique `external_id` and `planned_workout_id` indexes apply. |

Controllers and services must resolve records through the signed-in owner's profile and plan, even when given a foreign ID. Pure calculations take explicit inputs, never request context. Two-rider specs cover ownership, scoping, preview and sync.
