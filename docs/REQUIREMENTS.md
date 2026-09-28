# CycleFar Functional Requirements

Requirement IDs are intended to be referenced in RSpec descriptions and implementation commits. These are acceptance criteria, not a statement that every behaviour is implemented. See [STATUS.md](STATUS.md) and the [2026-09-24 implementation review](REVIEW.md) for verified behaviour and outstanding gaps.

## Current authentication scaffold

Rails authentication was generated after the original V1 requirements. The application now has a public homepage with Sign In and Register, email/password self-registration, sign-out, password-reset routes and a default authentication check on private controllers. Profiles, plans and sync records have required user ownership in PostgreSQL. Controlled provisioning, configured SMTP and an automated two-rider matrix are implemented; the target-data rehearsal, live mail verification and Milestone 11 acceptance work remain open. The `USR-*` requirements below describe the independent-rider release; see [ARCHITECTURE.md](ARCHITECTURE.md) and [STATUS.md](STATUS.md) for current state.

## 0. Product identity

### BRD-001 CycleFar naming

The product is named **CycleFar**.

Acceptance criteria:

- User-facing application chrome and primary product references use `CycleFar`.
- The Rails application/project identifier is `cycle_far` and application module is `CycleFar`.
- `cyclefar.com` is the owned future domain. The V1 application remains local; the separately added AWS infrastructure templates are documented in [infra/](../infra/README.md) and do not establish a deployed service.
- Core domain model/table names remain brand-neutral.
- External ownership identifiers created by CycleFar, such as Intervals.icu `external_id`, use a stable `cyclefar-` namespace.

## 1. Settings

### SET-001 Current FTP

The application stores each rider's current FTP in their user-owned settings/profile record. The original V1 release has one enabled rider.

Acceptance criteria:

- FTP is required and must be a positive integer.
- Plan setup defaults its FTP field from Settings.
- Changing Settings FTP after a plan exists updates future planned workout wattage displays/exports.
- Completed workouts retain the FTP and watt targets that applied when they were completed.
- FTP changes are recorded in a lightweight FTP history table for future use, although V1 has no FTP-history UI.

### SET-002 Intervals.icu API key

Settings allow an optional Intervals.icu API key.

- Store it encrypted at rest using Active Record Encryption.
- Never log it.
- Display a masked value after save.
- The sync action must fail gracefully when the key is absent or rejected.

## 2. No-plan state

### PLN-001 Empty home

When there is no active plan, `/` shows a calendar from Monday of the previous week through the end of the current month with a clear `Create training plan` action. The no-plan calendar has no workout, time-off or weekly-summary controls.

## 3. Plan setup

### PLN-010 Single configuration page

Plan configuration is one long form, not a multi-step wizard.

Required fields:

- goal;
- discipline;
- start date;
- FTP;
- include Base phase?;
- progression mode;
- weekly availability.

For non-event goals:

- plan duration can be selected from presets (1, 3, 6 months) or entered as a custom duration.

For event goal:

- event name required;
- event date required;
- event discipline required (default to plan discipline);
- distance km optional;
- elevation metres optional;
- expected duration optional.

### PLN-011 Weekly availability

The rider configures a repeating Monday–Sunday template.

Each active day has:

- exact duration in minutes;
- workout intent.

Workout intent may be broad:

- Intervals
- Endurance
- Recovery

or specific:

- VO2 Max
- Threshold
- Sweet Spot
- Tempo
- Endurance
- Recovery

Days not configured are rest days and appear empty on the calendar.

The app trusts the rider's choices, including back-to-back intensity days, but may display non-blocking warnings for risky schedules.

### PLN-012 Progression mode

The rider chooses either:

1. Continuous progression; or
2. Hard/recovery cycle, specifying the number of hard weeks before each recovery week.

### PLN-013 Preview

Submitting configuration first creates a preview, not a persisted active plan.

Preview shows:

- plan start/end;
- phase names and date ranges;
- weekly availability;
- recovery-week pattern;
- FTP assessment dates;
- target event + taper where applicable;
- projected weekly duration/TSS progression.

The rider may go back and edit the configuration, then confirm to create the plan.

### PLN-014 One active plan

Only one active plan may exist per rider. The original V1 release has one enabled rider.

Major plan settings are immutable after confirmation:

- goal;
- discipline;
- event definition;
- phase structure choices.

To change these, the rider archives/deletes the active plan and creates another.

Archiving/deleting an active plan:

- removes all uncompleted future/planned workouts;
- keeps completed workouts and their parent archived plan records as history;
- does not expose a History screen in V1.

## 4. Plan structure

### PLN-020 Phases

Plans use named phases:

- Base (optional)
- Build
- Speciality
- Taper (event plans only)

The application calculates phase lengths automatically from total available duration. The rider does not configure phase lengths.

### PLN-021 Discipline specificity

Speciality is goal/discipline specific. Build may also use discipline as a secondary input. Base remains mostly generic.

### PLN-022 Taper/event

Event plans automatically include a taper and a short opener workout shortly before the event. Taper/opener scheduling may override the normal weekly template.

The target event appears as a special calendar item showing:

- event name;
- distance when supplied;
- elevation when supplied;
- discipline;
- expected duration when supplied.

## 5. Calendar

### CAL-001 Continuous calendar

The home screen for an active plan is a continuous, vertically scrolling calendar of Monday–Sunday weeks spanning the entire plan. Do not paginate by month.

Month boundaries should be obvious but must not interrupt the continuous week layout.

### CAL-002 Workout cards

For structured workouts within the next 14 days, calendar cards show:

- generated descriptive name;
- workout type;
- duration;
- main interval summary;
- target power range(s);
- mini workout profile graph;
- planned TSS;
- planned IF;
- planned work.

For workouts beyond 14 days, show only:

- workout type;
- duration;
- phase;
- short purpose/description.

Do not show a detailed graph until the workout becomes structured.

### CAL-003 Phase/load display

Calendar visibly indicates phase boundaries and recovery weeks.

Each week displays totals for:

- planned duration;
- planned TSS;
- planned work.

The overall plan must make weekly planned load progression easy to see.

A full-width TSS chart above the calendar shows one bar per plan week, using the same totals as the weekly summaries and including empty weeks.

### CAL-004 Completed/overdue states

- Completed workouts remain visible with a clear completed indicator.
- A planned workout whose date is in the past remains visible and actionable as `Awaiting status`.
- It is not automatically marked missed.
- Workouts explicitly resolved as missed remain visible with a `Missed` indicator (see MIS-001); moving a workout keeps it planned on the destination date.

## 6. Rolling 14-day horizon

### GEN-001 Detail horizon

At all times, workouts whose dates fall in the next 14 calendar days should have generated structures.

- The rolling horizon is inclusive of today.
- When a new date enters the horizon, generate its structure automatically on a normal application request/job boundary.
- Do not silently regenerate already structured workouts merely because a day has passed.
- A changed FTP recalculates future target watts/metrics without changing the stored percentage-based structure.

## 7. Workout details/actions

### WKO-001 Detail view

Selecting a workout opens a detailed view (Turbo modal preferred) showing:

- name and purpose;
- phase/type/subtype;
- full interval breakdown;
- full profile graph;
- duration;
- FTP basis/current target watts;
- planned TSS, IF and work;
- concise reason the workout is in the plan.

Actions:

- Shuffle
- Change workout
- Move
- Mark completed
- Mark missed (for past/current workouts as appropriate)

### WKO-002 Generated names

Names are descriptive, not fanciful, e.g. `Threshold 3x12`, `VO2 Max 5x4`, `Endurance 90 min`.

### WKO-009 Endurance profiles

New endurance workouts randomly select sustained, alternating low/high, or undulating endurance profiles. The selected profile is saved with the workout and remains stable when viewed again. All three fit the requested duration and keep their main sets within endurance power ranges. Forecasts remain deterministic.

### WKO-003 No step editing

The rider cannot manually edit individual interval steps in V1.

### WKO-004 Shuffle

Shuffle offers:

- Same
- Easier
- Harder
- Shorter
- Longer

Same:

- preserves subtype and duration;
- produces a different valid structure;
- aims to keep IF/TSS close to the original.

Easier/Harder:

- affect only this workout;
- normally preserve subtype and duration;
- modify structure/progression level, not arbitrary wattage hacks;
- do not offer replanning purely because of this manual harder/easier choice.

Shorter/Longer:

- change duration in 15-minute increments;
- minimum duration is 30 minutes;
- no maximum duration;
- may exceed the day's originally configured availability because this is an explicit rider choice.

### WKO-005 Change workout

The rider may choose a different workout type and/or duration.

The workout type selector includes an **Opener**. An opener uses the canonical 30–45 minute event-activation structure.

If this materially changes training load or changes between easy/intensity intent, show an optional `Replan upcoming workouts` proposal. The rider may dismiss it and keep the rest of the plan unchanged.

### WKO-006 Move

The rider may move a workout by opening it and choosing a new date. No drag-and-drop in V1.

V1 assumes one cycling workout per date. The date picker should prevent moving onto a date that already contains another cycling workout; the rider can move that workout first.

### WKO-007 Copy

The rider may copy a planned structured workout to another empty date inside the plan. The copy retains the source's canonical percentage-based step structure and is calculated using the rider's current FTP. Copying does not alter the source workout or replan the rest of the calendar.

### WKO-008 Add workout

An empty calendar date inside the plan links to an add-workout form. The rider chooses a workout type and duration; CycleFar generates its canonical structured workout using the current FTP. The date must not be occupied, a target-event date or within time off.

## 8. Completion and feedback

### FBK-001 Manual completion

Completion is always manual in V1.

When marking completed, collect:

- RPE: integer 1–10;
- completion quality:
  - Completed as planned
  - Struggled but completed
  - Could not complete

After completion, freeze the workout as an immutable snapshot of:

- structure;
- FTP used;
- target watts;
- duration;
- TSS/IF/work estimates;
- submitted feedback.

### FBK-002 Adaptation proposal

Feedback may produce a proposed adaptation to the next 14 days.

- Show a concise before/after summary and reason.
- The rider accepts or rejects the entire proposal atomically.
- Do not silently apply it.
- V1 does not need a persistent user-visible history of accepted/rejected proposals.

Repeated feedback may alter longer-term progression state used when later workouts are structured, without rewriting the long-term schedule unnecessarily.

### FBK-003 Late completion

A rider may mark an old awaiting-status workout completed at any later date.

Its feedback may trigger an adaptation proposal only if the next upcoming workout has not already been completed.

## 9. Missed workouts

### MIS-001 Resolution choices

When the rider marks a workout missed, offer:

1. Leave the remaining plan unchanged;
2. Move this workout to another suitable empty date;
3. Replan upcoming workouts.

`Replan upcoming workouts` changes only the near-term block (normally next 7–14 days), respecting fixed rider availability/intensity-day intent.

Workouts resolved by leaving the plan unchanged or replanning are retained on the calendar with a `Missed` status. A moved workout remains planned on its new date.

## 10. Schedule changes

### SCH-001 Availability changes

After plan creation, weekly availability can be changed:

- for one specific calendar week; or
- from a chosen date onward.

The app replans affected future prescriptions around the revised template. Past and completed workouts are not changed.

## 11. Time off

### OFF-001 Planned time off

The rider can add a time-off period with:

- start date;
- end date;
- reason: Holiday / Illness / Recovery / Event / Other.
- optional name, such as `France` for a Holiday.

The plan removes/avoids workouts during that period and replans around it.

For Illness or Recovery, the rider additionally chooses the duration of an easier return-to-training period. The engine ramps intensity/load back toward the normal plan across that user-selected period. Holiday, Event and Other time off resume without a return ramp.

## 12. FTP assessments

### FTP-001 Automatic placement

The engine automatically places `FTP Test` calendar items/workout replacements at sensible points in sufficiently long plans.

- The rider does not configure the testing frequency.
- An FTP test replaces that day's normal workout.
- The app does not prescribe a particular FTP testing protocol.
- FTP-test items have no planned TSS/IF/work because the protocol is unknown.
- After testing, the rider manually changes FTP in Settings.

## 13. Training load control

### LOAD-001 Planned metrics

Structured planned workouts calculate estimated:

- Normalized Power;
- Intensity Factor;
- TSS;
- total work in kJ.

The calendar may omit NP, but the metrics service may retain it internally.

### LOAD-002 Weekly progression cap

The engine controls the rate of planned TSS increase between comparable hard weeks using a fixed V1 default; the rider does not choose conservative/standard/aggressive modes.

Recovery and taper weeks are deliberate load reductions and should not be treated as the baseline for the subsequent hard-week increase cap.

## 14. Intervals.icu

### ICU-001 Manual sync

A `Sync to Intervals.icu` button syncs exactly the next two upcoming structured workouts.

- No automatic background syncing in V1.
- API-key auth only.
- Use stable `external_id` values so repeated syncs upsert rather than duplicate.
- If one of the previously synced next-two workouts is no longer in the next-two set because it was moved/deleted/replanned, remove or update the corresponding app-owned Intervals.icu event as appropriate.
- Never delete unrelated Intervals.icu calendar events.

See `INTERVALS_ICU.md`.

## 15. Units and dates

- Distance: kilometres.
- Elevation: metres.
- Calendar week: Monday–Sunday.
- Workout scheduling: date only; no preferred time-of-day feature.
- Store date concepts as Rails `date` where possible to avoid timezone drift.

## 16. Planned independent-rider release

These are the acceptance criteria for planned Milestone 12. Much of the ownership and isolation code, public registration and automated two-rider coverage are present locally; deployment with additional riders remains pending the target-data migration rehearsal, live mail delivery and open Milestone 11 work. This section does not advance the current milestone. Preserve deterministic training rules and completed-workout immutability. There is one rider per `User`, with no coach or shared-plan permissions.

### USR-001 Account registration and authentication

- The public homepage offers Sign In and Register. A new rider can create an account with an email address and confirmed password, is signed in, and sees their private calendar. A signed-in rider cannot create another account through the registration form.
- An authorized operator can also provision or invite an independent rider account. The rider signs in with the existing email/password session flow, can sign out through a visible control, and can receive a working password-reset email without account enumeration.
- Do not expose Google/social sign-in, coach, team or shared-plan flows in this release.
- Do not deploy multi-rider access against legacy global training data before USR-002 through USR-007 and the USR-008 isolation gate pass.

Automated coverage target: public-home and registration request specs, plus authentication/provisioning specs for a second rider, sign-out and draft clearing, password-reset delivery with mail stubbed, old-session invalidation and indistinguishable reset-request responses.

### USR-002 One owned rider profile and FTP history

- Each `User` can have at most one `RiderProfile`; first Settings save establishes it when the rider supplies the required FTP. Thereafter that rider has one profile. Its encrypted Intervals.icu API key and all `FtpReading` rows belong to that rider through the profile.
- Replace the global `RiderProfile.current`/`id = 1` contract. A unique, required `rider_profiles.user_id` foreign key enforces at most one profile per user; concurrent first Settings saves must establish only one profile safely.
- Updating FTP recalculates only that user's future plan metrics and watts. Both users' completed workout snapshots remain immutable.

Automated coverage target: model/database uniqueness and foreign-key specs, concurrent first-profile creation, two-user Settings/FTP service and request specs, and completed-history regression specs.

### USR-003 One active plan per user and archived history

- Each `TrainingPlan` belongs to one `User`. Each user may have at most one active plan and any number of archived plans; another user's active plan does not block plan creation.
- Replace the global partial active-plan index with a unique partial index on `training_plans.user_id` where `status = 'active'`, alongside a required user foreign key. Archive retains completed workouts and their parent plan as private history; uncompleted future prescriptions follow the existing archive policy. No separate History screen is required.
- Target events, phases, availability, workouts, time off and adaptation proposals inherit ownership through their plan. FTP readings inherit it through the profile. Completed records remain immutable.

Automated coverage target: two-user and concurrent plan-creation model/database specs, archive/history service specs, and request specs proving each user's calendar and plan actions see only their own records.

### USR-004 Owner-scoped reads and mutations

- Resolve the active plan and profile from the authenticated `Current.user`. Resolve every workout, proposal and time-off identifier through that user's owned plan, including detail, editing, completion, missed resolution, availability and archive actions.
- A valid ID owned by another user must neither disclose data nor mutate it. Missing and foreign IDs receive the same not-found response. Domain services receive an explicit owned plan or profile; pure training calculations remain independent of `Current.user`.

Automated coverage target: two-user request matrix for every training read and mutation route, guessed-ID/not-found equivalence, and service specs proving cross-user inputs cannot recalculate or mutate another rider's records.

### USR-005 Same-browser preview isolation

- Bind the session-backed plan preview draft to the authenticated user or clear it when the account changes. Another user signing in with the same browser cannot view, edit or confirm the prior user's draft. A stale draft cannot create a plan for the wrong user.
- Preserve preview, Back to edit and confirmation for the same user.

Automated coverage target: request specs for A sign-out/B sign-in in one browser, stale draft confirmation rejection, and the same-user preview/edit/confirm flow.

### USR-006 Owner-scoped Intervals.icu sync

- Use the signed-in rider's own profile/API key, active plan and sync records for next-two selection and reconciliation. `IntervalsIcuSync` has a required `user_id` so a record remains attributable after its workout is deleted.
- Keep stable `cyclefar-workout-<planned_workout.id>` external IDs. A rider's sync may upsert or delete only that rider's CycleFar-owned remote events, including detached stale records; it must never inspect another rider's key or sync records. Preserve retry-safe partial-failure behavior.

Automated coverage target: stubbed HTTP two-user adapter/service specs with distinct keys, next-two sets and stale/detached records; repeat-sync and partial-failure specs; assertions that the other user's remote events are untouched.

### USR-007 Explicit-owner legacy migration

- Before adding required ownership constraints, inspect each target database's users, singleton profile, FTP readings, plans, completed workouts and linked or detached sync rows. Report counts and the selected existing owner without revealing API keys.
- Require an explicitly selected existing account for legacy training data. Never infer the owner from the first user, current session or record order. If ownership is ambiguous or inconsistent, fail before partial assignment. Preserve completed structures, snapshots, FTP history and existing external IDs exactly.
- Backfill profile, plans and sync rows to that owner, then enforce required foreign keys, unique profile ownership and per-user active-plan uniqueness. Rehearse on a representative database copy and document recovery before cutover; resolve the known local development users/sessions migration conflict without deleting rider data.

Automated coverage target: migration/preflight specs for empty, valid single-owner, ambiguous and inconsistent data; preservation checks for completed snapshots, FTP readings and detached sync IDs; database-constraint specs and a documented copy-of-data rehearsal.

### USR-008 Two-user release gate

- Enable multiple rider accounts only after owner schema, controller and service scoping, preview isolation, sync scoping and provisioning are complete together. Verify Settings, calendar, plan creation/archive, workout actions, feedback/adaptation, missed workouts, schedule/time off, FTP lifecycle, archived history and Intervals.icu sync with two users.
- Keep the current Milestone 11 open until its own exit criteria and required gates pass. Update [STATUS.md](STATUS.md) when a milestone actually completes; do not report planned per-user work as delivered.

Automated coverage target: end-to-end two-user regression matrix with foreign-ID attempts, full RSpec suite, Zeitwerk check and configured lint/security checks before Milestone 12 completion.
