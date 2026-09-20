# CycleFar UX Specification

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
- completed or awaiting-status badge when applicable.

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

- clearly spans/marks affected dates with reason.

## 6. Workout detail modal

Use a Turbo Frame modal if practical so the rider maintains calendar context.

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
- Complete
- Missed (when relevant)

## 7. Shuffle dialog

Options displayed as explicit choices:

- Same
- Easier
- Harder
- Shorter by 15 min
- Longer by 15 min

Shorter can be repeated down to a 30-minute minimum. Longer can be repeated without a hard maximum.

Before applying, show the new duration/TSS/IF and a compact replacement profile when feasible.

## 8. Change-workout dialog

Allow:

- new type;
- new duration.

Generate the new structure rather than exposing interval-step editing.

If materially different, after generation present:

`This changes the load/intent of the day. Replan the next 14 days around it?`

Buttons:

- Keep rest of plan unchanged
- Replan upcoming workouts

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

## 10. Awaiting-status flow

Past uncompleted cards show `Awaiting status`.

Opening them prioritises:

- Mark completed
- Mark missed

Mark missed then offers:

- Leave plan unchanged
- Move workout
- Replan upcoming workouts

## 11. Availability changes

A form based on the same weekly grid as setup.

Scope choice:

- This week only
- From [date] onward

Preview affected future workouts before applying when the change causes significant replanning.

## 12. Time off

Form:

- Start date
- End date
- Reason

If reason = Illness or Recovery:

- additional field for user-selected return-to-training duration (days/weeks; normalise internally to days).

After save, show a concise summary of workouts removed/replanned.
