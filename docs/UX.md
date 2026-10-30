# CycleFar UX Specification

This document describes the interaction design as implemented. Controls not described here do not exist.

## Branding

- Display the product name as **CycleFar** in the application shell/header.
- Keep branding restrained; the calendar remains the primary visual focus.

## Navigation

Keep navigation minimal:

- Calendar (home)
- Settings
- When an active plan exists: Manage schedule / Add time off / Delete plan actions may sit in the calendar header rather than requiring a permanent nav item.

No History page in V1.

## Authentication and registration screens

- The public homepage offers **Sign In** and **Register**; private pages redirect to sign-in.
- Sign-in takes email and password and links to **Forgot password?** and **Register**.
- Registration takes email, password and confirmation, then signs the rider in.
- The reset request shows the same confirmation whether or not the address exists; the emailed link opens the password form.
- Signed-in pages show the account and **Sign out**; Calendar and Settings links are hidden on public pages.

## Independent-rider account flow

Every screen shows only the signed-in rider's profile and plan. Links to another rider's workouts, proposals or time off behave like missing records. Archived plans keep their history privately; there is no History page, social sign-in, coach, team or shared-plan UI.

A preview draft belongs to its creator: if another rider signs in on the same browser, they start from their own form and can't open or confirm it.

## 1. No-plan home

Purpose: show the current calendar while getting the rider into plan creation immediately.

Content:

- short CycleFar product sentence;
- `Create training plan` primary button;
- secondary link to Settings if FTP is not yet configured.
- four Monday–Sunday calendar weeks starting Monday of the previous week, without workout cards or weekly summaries.

## 2. Settings

Fields:

- Current FTP (watts)
- Intervals.icu API key

Behaviour:

- explain briefly that changing FTP updates future planned targets, not completed workouts;
- API key is password-style/masked after save;
- FTP history sits below the form, newest first, with the current reading labelled. Edit changes watts or date; Delete asks for confirmation and is hidden for the last reading. Saving a changed FTP adds a reading dated today; the newest reading sets future targets.
- A changed FTP refreshes workouts already synced to Intervals.icu, and the success message gives the count. If the refresh fails, the save still succeeds and the rider is told to check the API key and retry with Sync.
- there is no `Test connection` button.

## 3. Create-plan configuration

One long page, broken into visually distinct sections rather than a wizard.

### Goal

Radio/cards:

- General Fitness
- Increase FTP
- Improve Endurance
- Improve Climbing
- Prepare for an Event

### Discipline

Shown only for event goals, as a required selector beside the event name and date, with the helper "Shapes the workout mix as your event approaches." It defaults to Road and keeps its value across goal switches, validation errors and Back to edit. Non-event goals never show a discipline (the internal Road default is never exposed).

- Road
- Gravel
- MTB
- Ultra / Endurance

### Timing

- Start date
- Non-event: one Plan length selector with 1 month / 3 months / 6 months / Custom weeks. Show Custom whole weeks only when selected, with a four-week minimum. Show the Rails-calculated end date as inputs change.
- Event: hide duration inputs and explain “Your plan runs from your start date to your event date.” The event date determines the end, with at least 28 days after start.
- Disable hidden inactive controls for validation/keyboard interaction, while retaining their draft values through toggles, validation errors and Back to edit.

### Event details (conditional)

- Event name *
- Date *
- Discipline *
- Native “Additional event details (optional)” disclosure contains expected riding time, distance km and elevation m.
- Riding time influences taper length (normally seven days, fourteen for over five hours if the plan allows); distance/elevation are calendar information.
- Keep disclosure state and entered values when editing; open it automatically for active optional-field errors.
- Non-event mode hides/disables all Target event controls.

### Fitness

- FTP prefilled from Settings
- Include Base phase? checkbox/toggle

### Progression

- Continuous progression
- Hard/recovery cycle
  - if selected: hard weeks before recovery week

### Weekly availability

A Monday–Sunday grid works well on desktop.

For each day:

- enabled checkbox/toggle;
- duration;
- Session type selector, named with its weekday for assistive technology.

Session type choices:

- Broad: Intervals — chosen for your goal / Endurance / Recovery
- Specific: VO2 Max / Threshold / Sweet Spot / Tempo / Endurance / Recovery

Explain at the grid that the goal only picks the workout type on broad Intervals days; Endurance and Recovery stay as chosen, unselected days are rest, and the goal never adds days or time. Specific intensity choices keep their type in normal weeks (recovery weeks and taper can override them). Unselected days aren't validated.

Show warnings inline for patterns such as several hard days in a row, but never block submission solely on training-quality warnings.

Primary action: `Preview plan`.

## 4. Plan preview

This is a review screen, not an editable form.

Show:

- goal; Event discipline only for event plans;
- date range;
- event summary if applicable;
- phase timeline;
- weekly template;
- recovery pattern;
- taper/opener details;
- projected weekly duration and TSS, preferably as a compact bar/line visual plus numbers.

Actions:

- `Back to edit`
- `Create plan`

## 5. Calendar/home

### Overall layout

A continuous stack of calendar weeks, Monday–Sunday, from plan start through plan end. Month labels appear as the weeks cross month boundaries, but there are no previous/next month controls.

Desktop-first layout can assume meaningful horizontal width. At narrower widths, preserve readability with local horizontal calendar scrolling rather than collapsing workout information into unusable cards.

### Header

Include:

- plan goal summary; discipline only for event plans, including when displaying existing plans;
- current FTP;
- `Sync all structured workouts to Intervals.icu`;
- `Change availability`;
- `Add time off`;
- destructive `Delete plan` in a secondary menu/action area; it is labelled `Archive plan` once the plan has completed workouts, which are retained.

### Weekly load chart

A full-width TSS bar chart sits above the calendar, one bar per week (including empty weeks), using the same totals as the weekly summaries; missed workouts count.

If load reductions can't keep an upcoming hard week within the 8% growth target, an advisory panel above the calendar says how many weeks are over and suggests editing that week's availability or using Easier, Shorter or Change workout. A collapsed **Review affected weeks** table lists projected and target TSS, with **Edit this week** (prefilled availability form) and **View in calendar** links.

### Phase bands

Visually label Base / Build / Speciality / Taper ranges. Recovery weeks should be distinguishable without needing a legend/filter.

### Week row

Each week has seven date columns plus a compact weekly summary area containing:

- total duration;
- total TSS;
- total work.

### Structured workout card (within 14 days)

Show enough to understand it without opening:

- descriptive name;
- duration;
- type;
- main set summary;
- power target range;
- mini skyline/profile graph;
- TSS / IF / kJ in compact form;
- completed, awaiting-status or missed badge when applicable. Missed cards remain visible with muted workout details;
- under the completed badge, ridden TSS when a ride file with power is attached, and the recorded RPE.

Main-set summaries keep under/over and activation efforts separate and show both ends of a ramp. Planned watts use current FTP; completed watts use the frozen snapshot.

### High-level workout card (>14 days)

Show:

- type;
- duration;
- phase;
- one-line purpose.

Do not imply that a detailed workout exists yet.

### Special calendar items

Event:

- distinctive card;
- name, discipline, optional distance/elevation/duration.

Time off:

- marks affected dates, using the optional name as the heading; unnamed Event time off is labelled `Time off`. Named non-event periods also display their reason.

Empty date headings offer Add Workout. The form accepts type (including Opener) and duration. The service rejects occupied dates, dates outside the plan, target-event dates and time-off dates.

## 6. Workout detail

Workout detail is a full page with Back to calendar, a large graph, zone-coloured step cards and inline action forms. It is not a Turbo Frame modal.

Sections:

1. Header: name, date, phase, type, duration.
2. Large workout profile graph.
3. Interval breakdown table/list.
4. Metrics: FTP basis, TSS, IF, work.
5. `Why this workout?` concise generated explanation based on deterministic rules.
6. Actions.

Actions:

- Shuffle
- Change workout
- Move
- Copy (planned structured regular workouts only)
- Complete
- Missed (when relevant)
- Remove workout (planned/missed workouts in an active plan, including outlines; asks for confirmation)

**Ride file (FBK-004).** Completed workouts in the active plan can upload, replace or remove one FIT file. The section compares planned and ridden duration, NP, IF, TSS and work, and shows ridden average power, heart rate and the completion FTP. A ride without power shows `No power data`; a ride on a different date shows a non-blocking warning. Removal asks for confirmation.

**Remove** returns to the calendar with that date empty and nothing else changed; the message explains that manual Sync updates Intervals.icu. Completed workouts can't be removed.

**Copy** places a copy on an empty date in the same plan, recalculating metrics at current FTP without replanning.

**Move** (and missed-workout Move) keeps the structure for same-phase moves of up to seven days; otherwise it regenerates for the destination, keeping type, duration and variation. Both reject occupied dates, dates outside the plan or its phases, time off and the event date, and show non-blocking load warnings, including for weeks beyond the detail window.

**Openers** support Change, Move and completion with RPE and quality; their feedback never proposes progression changes. Opening an outline due today or earlier generates its detail for completion without touching other workouts. Once completed, structure, FTP, watts, metrics and feedback are frozen.

## 7. Shuffle controls

Options displayed as explicit choices:

- Same
- Easier
- Harder
- Shorter by 15 min
- Longer by 15 min

Shorter can be repeated down to a 30-minute minimum. Longer can be repeated without a hard maximum.

Easier/Harder keep type and duration, and only accept a replacement whose actual and displayed whole-number TSS both move the right way. Interval sessions step through their ladders; Endurance and Recovery switch between aerobic profiles (they have no level and power targets are never lowered continuously). For a 60-minute Endurance ride, Easier can go from alternating (45 TSS) to sustained (44) and then stops. At the limit the workout is unchanged and the rider sees `No lower-load option is available at this duration. Try Shorter or Change workout.` (Harder says `higher-load` and `Longer`). Same keeps rotating valid profiles.

Buttons apply immediately and return to the updated detail page. A replacement preview would be desirable but doesn't exist.

## 8. Change-workout dialog

Allow:

- new type, including Opener;
- new duration (regular workouts at least 30 minutes; openers 30–45 minutes).

Generate the new structure rather than exposing interval-step editing.

If materially different, after generation present:

`This changes the load/intent of the day. Replan the next 14 days around it?`

Buttons:

- Keep rest of plan unchanged
- Replan upcoming workouts

The choice is saved as a proposal on the workout detail page. The changed workout stays fixed; accepting re-prescribes the following 14 days atomically, using the availability that applies on each date.

## 9. Completion flow

A compact form:

- RPE 1–10
- Completion quality: Completed as planned / Struggled but completed / Could not complete

Submit marks the workout complete and freezes it.

If adaptation is warranted, next show an adaptation proposal:

- why it is suggested;
- which upcoming workouts change;
- before/after summary;
- Accept all / Reject all.

On the calendar, a feedback proposal shows its reason, links to each affected workout, and Current / Proposed tables (name, level where relevant, duration, TSS, IF, work) at the rider's current FTP. A bias change shows current and resulting values after clamping; it affects intensity outlines as they enter the next 14 days, never workouts already structured. Targets only fall within today through day 13. Viewing or refreshing a comparison never applies it.

Unavailable comparisons show a generic explanation and Reject all only. Expired, stale or unverifiable proposals (feedback or material-change) show dismissal guidance with no Accept, and direct acceptance is refused. Dismissing changes nothing; changing the workout again can produce a fresh material-change proposal. Completed feedback is never rewritten.

## 10. Awaiting-status flow

Past uncompleted cards show `Awaiting status`.

Opening them prioritises:

- Mark completed
- Mark missed

Mark missed then offers:

- Leave plan unchanged
- Move workout
- Replan upcoming workouts

Leave unchanged and Replan retain the source card as `Missed`; Move keeps it planned on its new date. No automatic missed resolution occurs.

## 11. Availability changes

The same weekly grid as setup, prefilled with the schedule for the week containing the chosen date. The date defaults to today (clamped to the plan) or comes from a load-guidance link; a date outside the plan shows an alert.

Scope choice:

- This week only
- From [date] onward

Submitting applies the change and returns to the calendar. A preview of significant changes is a design goal, not implemented.

## 12. Time off

Form:

- Start date
- End date
- Reason: Holiday / Illness / Recovery / Event / Other
- Optional name, for example `France`

If reason = Illness or Recovery:

- additional field for user-selected return-to-training duration (days/weeks; normalise internally to days).

Saving confirms that time off was added and training replanned, without a per-workout summary. Illness and Recovery return workouts show their return-stage purpose, with reduced duration and power, then resume one level below the latest comparable pre-break session. Holiday, Event and Other have no return ramp and resume from that baseline. See [TRAINING_ENGINE.md §39](TRAINING_ENGINE.md#39-time-off).
