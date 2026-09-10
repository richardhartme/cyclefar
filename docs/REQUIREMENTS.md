# CycleFar Functional Requirements

Requirement IDs are intended to be referenced in RSpec descriptions and implementation commits.

## 0. Product identity

### BRD-001 CycleFar naming

The product is named **CycleFar**.

Acceptance criteria:

- User-facing application chrome and primary product references use `CycleFar`.
- The Rails application/project identifier is `cycle_far` and application module is `CycleFar`.
- `cyclefar.com` is recorded only as the owned future domain; V1 must not add deployment behaviour around it.
- Core domain model/table names remain brand-neutral.
- External ownership identifiers created by CycleFar, such as Intervals.icu `external_id`, use a stable `cyclefar-` namespace.

## 1. Settings

### SET-001 Current FTP

The application has a singleton rider settings/profile record containing the current FTP in watts.

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

When there is no active plan, `/` shows a clear `Create training plan` action rather than a blank calendar.

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

Only one active plan may exist.

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

### CAL-004 Completed/overdue states

- Completed workouts remain visible with a clear completed indicator.
- A planned workout whose date is in the past remains visible and actionable as `Awaiting status`.
- It is not automatically marked missed.
- Missed/skipped workouts are removed once the rider explicitly resolves them as missed.

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

If this materially changes training load or changes between easy/intensity intent, show an optional `Replan upcoming workouts` proposal. The rider may dismiss it and keep the rest of the plan unchanged.

### WKO-006 Move

The rider may move a workout by opening it and choosing a new date. No drag-and-drop in V1.

V1 assumes one cycling workout per date. The date picker should prevent moving onto a date that already contains another cycling workout; the rider can move that workout first.

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
- reason: Holiday / Illness / Recovery / Other.

The plan removes/avoids workouts during that period and replans around it.

For Illness or Recovery, the rider additionally chooses the duration of an easier return-to-training period. The engine ramps intensity/load back toward the normal plan across that user-selected period.

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
