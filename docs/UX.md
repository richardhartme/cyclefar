# CycleFar UX Specification

This document combines the intended interaction design with current implementation notes from the 2026-09-24 review. Outstanding acceptance gaps are tracked in [REVIEW.md](REVIEW.md); proposed controls below must not be assumed to exist.

## Branding

- Display the product name as **CycleFar** in the application shell/header.
- Keep branding restrained; the calendar remains the primary visual focus.
- Do not expose `cyclefar.com` as though the local V1 were already a hosted service.

## Navigation

Keep navigation minimal:

- Calendar (home)
- Settings
- When an active plan exists: Manage schedule / Add time off / Delete plan actions may sit in the calendar header rather than requiring a permanent nav item.

No History page in V1.

## Authentication screens currently generated

Unauthenticated application requests redirect to the generated **Sign in** page. It accepts an email address and password and links to **Forgot password?**. The reset-request page accepts an email address and displays the same confirmation whether or not it matches a user; a token link opens the password-update form. The application layout still shows the normal Calendar and Settings navigation on these pages and has no sign-out link, although the sign-out route exists. There is no registration screen. Password-reset email delivery has not been configured or verified beyond the generated mailer.

## Planned independent-rider account flow

This is Milestone 12 design, not current behavior. An authorized operator provisions or invites a rider; the rider uses the existing email/password sign-in and a deliverable password-reset link. The application shell identifies the signed-in account and offers visible sign-out. There is no public registration, Google/social sign-in, coach, team or shared-plan UI in the first independent-rider release.

After sign-in, Calendar, Settings, plan setup and all workout actions show only that account's profile and plan. Each rider can have one active plan; archived plans retain private completed history without adding a History page. Foreign workout, proposal and time-off links respond like missing records, without showing another rider's details. Intervals.icu sync uses only the signed-in rider's key and owned events.

A preview draft belongs to the account that created it. If rider A signs out and rider B signs in in the same browser, B starts from B's own plan form and cannot open, edit or confirm A's preview. A's Back to edit and confirmation still work when A remains signed in. Request specs for these paths and the two-user UI routes are required by [USR-001–USR-008](REQUIREMENTS.md#16-planned-independent-rider-release).

## 1. No-plan home

Purpose: show the current calendar while getting the rider into plan creation immediately.

Content:

- short CycleFar product sentence;
- `Create training plan` primary button;
- secondary link to Settings if FTP is not yet configured.
- calendar starting Monday of the previous week and continuing through the end of the current month in the normal Monday–Sunday layout, without workout cards or weekly summaries.

## 2. Settings

Fields:

- Current FTP (watts)
- Intervals.icu API key

Behaviour:

- explain briefly that changing FTP updates future planned targets, not completed workouts;
- API key is password-style/masked after save;
- optional `Test connection` button is useful but not required for the first implementation milestone.

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

- Road
- Gravel
- MTB
- Ultra / Endurance

### Timing

- Start date
- Non-event: plan length presets 1 / 3 / 6 months + Custom
- Event: event date determines end of plan

### Event details (conditional)

- Event name *
- Date *
- Discipline *
- Distance km
- Elevation m
- Expected duration

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
- workout intent selector.

Intent selector may group choices:

- Broad: Intervals / Endurance / Recovery
- Specific: VO2 Max / Threshold / Sweet Spot / Tempo / Endurance / Recovery

Show warnings inline for patterns such as several hard days in a row, but never block submission solely on training-quality warnings.

Primary action: `Preview plan`.

## 4. Plan preview

This is a review screen, not an editable form.

Show:

- goal + discipline;
- date range;
- event summary if applicable;
- phase timeline;
- weekly template;
- recovery pattern;
- proposed FTP-test dates;
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

- plan goal/discipline summary;
- current FTP;
- `Sync next 2 to Intervals.icu`;
- `Change availability`;
- `Add time off`;
- destructive `Delete plan` in a secondary menu/action area.

### Weekly load chart

A full-width TSS bar chart sits above the calendar, with one bar per week, including empty weeks. It uses the same totals as weekly summaries. Current totals include retained missed workouts; REVIEW.md records the reporting question this raises.

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
- completed, awaiting-status or missed badge when applicable. Missed cards remain visible with muted workout details.

Current cards show name, duration, TSS, IF and a profile graph. Main-set summary, watt range and work kJ remain detail-view information rather than card fields; see REVIEW.md.

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

FTP Test:

- distinctive card labelled `FTP Test`;
- no invented workout graph/metrics.

Time off:

- marks affected dates, using the optional name as the heading; unnamed Event time off is labelled `Time off`. Named non-event periods also display their reason.

Empty date headings offer Add Workout. The form accepts type (including Opener) and duration. The service rejects occupied dates, dates outside the plan, target-event dates and time-off dates.

## 6. Workout detail

Current implementation: a full page with Back to calendar, a large graph, zone-coloured step cards and inline action forms. A Turbo Frame modal remains a design preference for preserving calendar context; it is not currently implemented.

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

Copy selects an empty date inside the same plan, retains canonical percentage steps and recalculates metrics at current FTP without changing the source or replanning. Openers support Change and Move, but currently lack the regular workout completion form (see REVIEW.md).

## 7. Shuffle controls

Options displayed as explicit choices:

- Same
- Easier
- Harder
- Shorter by 15 min
- Longer by 15 min

Shorter can be repeated down to a 30-minute minimum. Longer can be repeated without a hard maximum.

A replacement preview is desirable before applying. Current buttons apply immediately and redirect to the updated detail page; there is no replacement preview.

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

Current implementation: a material Change creates a persisted proposal and shows both choices on the workout detail page. The changed workout remains fixed; acceptance atomically re-prescribes the bounded following 14-day block using the effective availability template for each date.

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

Current proposals appear on the calendar with a reason and Accept all / Reject all buttons. Per-workout before/after summaries are outstanding (FBK-002).

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

A form based on the same weekly grid as setup.

Scope choice:

- This week only
- From [date] onward

Previewing significant changes remains a design goal. Current submission applies the availability change transactionally and redirects to the calendar.

## 12. Time off

Form:

- Start date
- End date
- Reason: Holiday / Illness / Recovery / Event / Other
- Optional name, for example `France`

If reason = Illness or Recovery:

- additional field for user-selected return-to-training duration (days/weeks; normalise internally to days).

After save, the app confirms that time off was added and future training replanned. It does not yet show a per-workout change summary. Holiday, Event and Other do not use a return ramp.
