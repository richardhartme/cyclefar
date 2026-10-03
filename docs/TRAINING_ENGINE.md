# CycleFar Deterministic Training Engine — V1

## 1. Purpose

This document defines a pragmatic, deterministic V1 training engine for indoor ERG-mode cycling. It is intentionally explicit so behaviour can be unit tested and later revised.

These rules are not a claim that there is one scientifically perfect training plan. They combine established power-training conventions with product heuristics suitable for a first implementation. Persist `engine_version = "v1"` so future versions can change rules deliberately.

These remain the intended rules. Implementation gaps are tracked in Jira and do not redefine them.

### Current implementation

Versioned constants live in `Training::V1::Rules` and `Planning::V1::Rules`. The pure `Training::V1::Progression` calculation applies accepted global intensity bias once to eligible outlines under the plan lock, clamps levels to 1–7, and respects saved recovery/taper/re-entry/load ceilings. Materialisation persists canonical steps, the fitted effective level and generation references atomically. Forecasts use explicit variations; initial endurance profiles are sampled and saved. Existing structured and completed workouts remain stable when the horizon rolls or FTP changes.

Feedback proposals now target regular planned structured workouts in today through day 13. They prefer the same subtype, then the Tempo/Sweet Spot/Threshold or VO2/Over-under family, then broad Intervals when the source used that intent. Nearby reductions use two calendar days after the source date: broad Intervals for struggled completion, any intensity session for failure, always within the current horizon. Difficult easy rides can lower the next same-subtype ride's existing ranges without changing its duration or turning it into intensity. `ProposalComparison` and `FeedbackLoadLimiter` generate read-only comparisons and recheck load ceilings/caps before atomic acceptance.

The accepted bias is still global, although repeated-pattern detection reads the last three completed workouts of the source subtype; per-family/subtype stored bias (§32) and bias-driven subtype substitution (§11) remain unimplemented. CYF-6 enforces seven-day expiry and proposal-time canonical-input validation for both feedback and material-change proposals. Relevant prescription, schedule, load or progression changes invalidate pending proposals; FTP-only metric recalculation does not. Legacy proposals without a verifiable baseline require dismissal. Ordinary and missed-workout moves now share destination-aware regeneration (§35), preserving eligible short structures and checking destination load, including outside the detail horizon. The shared weekly cap currently lowers intensity levels; the full sequence of alternate-variation/target/subtype reductions in §27 remains intended behaviour. Late-feedback suppression checks whether the next scheduled workout after the source is completed (§33). Due/overdue executable outlines can be individually materialised for manual completion without changing other workouts. Openers record feedback without progression adaptation, since no expected opener RPE band is defined. See [ARCHITECTURE.md](ARCHITECTURE.md) for service boundaries and [UX.md](UX.md) for presentation limits.

## 2. Non-negotiable engine constraints

1. No AI/LLM calls.
2. No randomness in plan-critical decisions except the explicitly requested initial endurance profile selection in section 15; persist that choice and keep forecasts deterministic.
3. Power prescriptions are ranges of FTP, not single watt targets.
4. Normal workouts are at least 30 minutes.
5. Generated structured workouts sum exactly to requested duration.
6. The rider's chosen workout-day intent is respected except for explicit recovery, taper, time-off/re-entry and FTP-test overrides.
7. The plan controls generated weekly load growth.
8. Manual rider overrides (Harder/Longer/etc.) may exceed normal generated-load rules because they are explicit choices; do not use the rider's manual override as evidence that future generated sessions should also be harder.
9. Completed workouts are immutable.
10. Any feedback-driven adaptation is proposed before application.

---

# Part A — Power model

## 3. Internal five-zone model

The rider does not see or customise these zones in V1.

| Zone | Name | FTP range |
|---|---|---:|
| Z1 | Recovery | <= 55% |
| Z2 | Endurance | 56–75% |
| Z3 | Tempo | 76–90% |
| Z4 | Threshold | 91–105% |
| Z5 | VO2 Max | 106–120% |

This is the first five bands of the commonly used FTP-based power-zone framework. V1 does not generate anaerobic/sprint prescriptions above 120% FTP.

### Sweet Spot

Sweet Spot is a workout subtype/intensity band, not a sixth zone:

- 88–94% FTP

It deliberately overlaps upper Tempo/lower Threshold.

### Default target bands used by generators

These are narrower execution bands inside the broader zones:

| Workout subtype | Default work target |
|---|---:|
| Recovery | 45–55% |
| Endurance | 60–72% |
| Tempo | 78–87% |
| Sweet Spot | 88–94% |
| Threshold | 95–102% |
| VO2 Max | 108–118% |
| Over-under “under” | 88–94% |
| Over-under “over” | 102–108% |

Do not generate >120% FTP in V1.

## 4. Watt display from ranges

For each future planned step:

```text
low_watts  = round(current_ftp * low_pct / 100)
high_watts = round(current_ftp * high_pct / 100)
```

The percentage range is canonical. Watt values are derived.

When FTP changes:

- planned/future step percentages stay unchanged;
- displayed/exported watts change automatically;
- planned work kJ changes;
- percentage-based IF/TSS normally remain essentially unchanged because FTP scales both numerator and denominator;
- completed workout watt snapshots never change.

---

# Part B — Plan construction

## 5. Plan duration

### Non-event plans

Presets:

- 1 month
- 3 months
- 6 months

Interpret presets as calendar-month advances from the chosen start date. A custom duration should be entered as whole weeks in V1.

Minimum custom duration: 4 weeks.

### Event plans

Plan runs from chosen start date through target event date.

Require event date to be at least 4 weeks after start date in V1. If the rider wants a shorter period later, that can be a future enhancement rather than inventing a compressed training model.

## 6. Plan weeks

Calendar weeks are Monday–Sunday.

A plan may start mid-week. The first partial calendar week is valid, but:

- do not use a partial first week as the reference for the weekly TSS growth cap;
- do not force extra workouts into earlier days to “make up” the partial week.

## 7. Phase allocation

Phases:

- Base — optional
- Build
- Speciality
- Taper — event only

Phase boundaries should align to Monday where practical, except plan start and event/taper end constraints.

### 7.1 Taper length first (event plans)

Choose taper duration before allocating other phases.

Default heuristic:

- expected event duration > 5 hours: 10–14 days, prefer 14 if plan length permits;
- expected duration 2–5 hours: 7–10 days, prefer 7;
- expected duration < 2 hours: 5–7 days, prefer 7;
- expected duration unknown: 7 days.

If the plan is too short to preserve at least one training week in every requested pre-taper phase, reduce taper to 7 days.

### 7.2 Allocate remaining time

If Base is included:

- Base: approximately 35% of remaining pre-taper training weeks
- Build: approximately 40%
- Speciality: approximately 25%

If Base is skipped:

- Build: approximately 60%
- Speciality: approximately 40%

Rounding rules:

1. Every included phase gets at least one calendar training week.
2. Allocate integer weeks using largest-remainder rounding.
3. Give leftover days caused by non-Monday boundaries to the adjacent phase that keeps boundaries closest to Mondays.
4. The final pre-taper day must connect directly to taper/event.

For non-event plans, use the same proportions without taper.

## 8. Recovery-week pattern

Recovery weeks are modifiers overlaying phases; they are not separate phases.

### Continuous progression

No pre-scheduled recovery-week cycle is inserted. Training still obeys weekly-load growth limits, and feedback/time-off can create easier periods.

### Hard/recovery cycle

If rider chooses `N` hard weeks before recovery:

- schedule N hard weeks;
- then one recovery week;
- repeat.

Alignment preference:

- if a planned recovery week naturally falls within one week of a Base→Build or Build→Speciality transition, align the recovery week immediately before the new phase when feasible;
- do not insert a recovery week inside the final taper.

### Recovery-week load target

Aim for approximately 55–70% of the most recent comparable hard week's planned TSS.

Recovery treatment may:

- replace intensity sessions with easier structured rides;
- reduce durations to roughly 60–80% of normal availability when required to achieve recovery load;
- preserve some easy riding continuity.

This is an explicit exception to the normal “exact configured duration” rule because the rider chose a recovery-week model and later confirmed that effective recovery should take priority.

Do not make a recovery ride hard merely to fill scheduled time.

## 9. Goal emphasis

Goal affects interval subtype selection, workout purpose and phase progression.

### General Fitness

Balanced aerobic development. Avoid over-specialising.

### Increase FTP

Bias toward Sweet Spot/Threshold with strategically placed VO2 Max work in Build/Speciality.

### Improve Endurance

Bias toward Endurance/Tempo/Sweet Spot and increasing fatigue resistance. Do not turn every interval day into VO2.

### Improve Climbing

Bias toward sustained Threshold, VO2 Max and over-under structures, especially later in the plan.

### Prepare for an Event

Base/Build are broadly developmental; Speciality is strongly discipline-specific.

## 10. Discipline emphasis

Discipline is secondary in Base, moderate in Build, strong in Speciality.

### Road

- sustained threshold;
- VO2 Max;
- over-unders/surging near threshold;
- balanced aerobic support.

### Gravel

- endurance durability;
- Sweet Spot/Tempo;
- sustained Threshold;
- some over-under work.

### MTB

- VO2 Max;
- repeated short aerobic-power intervals;
- over-under/repeated surge structures;
- enough endurance support to avoid becoming purely high intensity.

V1 deliberately avoids anaerobic/sprint >120% FTP even though real MTB training may include it.

### Ultra / Endurance

- Endurance;
- Tempo/Sweet Spot durability;
- sustained Threshold used sparingly;
- less VO2 emphasis than Road/MTB.

## 11. Broad Intervals subtype selection

When the rider explicitly chooses a specific subtype, use it (subject to recovery/taper/time-off overrides).

When the rider chooses broad `Intervals`, choose deterministically from these priority cycles.

Use a plan-level counter keyed by phase/goal or simply the ordinal number of broad interval prescriptions in that phase. Cycle through the list rather than choosing randomly.

### Base cycles

| Goal | Cycle |
|---|---|
| General Fitness | Sweet Spot → Tempo → Sweet Spot → Threshold |
| Increase FTP | Sweet Spot → Threshold → Sweet Spot → Threshold |
| Improve Endurance | Tempo → Sweet Spot → Tempo → Sweet Spot |
| Improve Climbing | Sweet Spot → Threshold → Tempo → Sweet Spot |
| Event | Sweet Spot → Tempo → Threshold → Sweet Spot |

Avoid VO2 as a routine Base choice in V1.

### Build cycles

| Goal | Cycle |
|---|---|
| General Fitness | Threshold → VO2 → Sweet Spot → Threshold |
| Increase FTP | Threshold → VO2 → Threshold → Sweet Spot |
| Improve Endurance | Sweet Spot → Threshold → Tempo → VO2 |
| Improve Climbing | Threshold → VO2 → Over-under → Threshold |
| Event | discipline cycle below |

Event Build cycles:

- Road: Threshold → VO2 → Sweet Spot → Threshold
- Gravel: Sweet Spot → Threshold → Tempo → VO2
- MTB: VO2 → Threshold → VO2 → Sweet Spot
- Ultra/Endurance: Sweet Spot → Threshold → Tempo → Sweet Spot

### Speciality cycles

For non-event goals:

- General Fitness: Threshold → VO2 → Sweet Spot → Tempo
- Increase FTP: Threshold → VO2 → Threshold → Over-under
- Improve Endurance: Sweet Spot → Tempo → Threshold → Sweet Spot
- Improve Climbing: Threshold → VO2 → Over-under → Threshold

For event plans, discipline takes priority:

- Road: Threshold → VO2 → Over-under → Threshold
- Gravel: Sweet Spot → Threshold → Tempo → Over-under
- MTB: VO2 → Over-under → VO2 → Threshold
- Ultra/Endurance: Tempo → Sweet Spot → Threshold → Tempo

### Feedback bias to selection

If repeated accepted feedback sets a negative intensity progression bias:

- broad Intervals may choose the next less demanding aerobic subtype in the cycle where appropriate (e.g. VO2 → Threshold, Threshold → Sweet Spot) for the next materialised workout;
- do not rewrite specific rider-selected VO2/Threshold days into a different subtype.

Positive bias increases progression level before changing subtype. Do not start adding extra VO2 days.

---

# Part C — Progression

## 12. Progression levels

Each structured intensity subtype has levels 1–7. Level is primarily based on position inside the current phase, then adjusted by feedback/recovery/load-cap constraints.

Base target levels by phase:

- Base: 1 → 4 across the phase
- Build: 3 → 6
- Speciality: 4 → 7

Compute phase fraction `f` from 0.0 to 1.0 using workout date inside the phase, then map evenly onto the phase's level range.

Example:

```text
level = min_level + floor(f * (max_level - min_level + 1))
clamp to min_level..max_level
```

Then apply accepted progression bias `-2..+2` and clamp 1..7.

### Recovery week

Cap intensity-workout replacement level at 1 and normally replace it with Recovery/Endurance rather than performing the nominal hard subtype.

### Return from illness/recovery

See section 39; cap progression during the re-entry period.

### TSS cap

If the planned week would violate load growth, lower generated progression levels until compliant before considering any other generated-load reduction.

## 13. Intensity progression philosophy

Progress primarily by increasing sustainable time-in-zone and/or reducing recovery, not by continuously pushing FTP percentage upward.

This is important for ERG workouts: a level increase should usually make the session more demanding through structure while preserving the intended physiological target.

## 14. Template ladders

These are canonical main-set families. The exact-duration fitter surrounds them with appropriate warm-up/cool-down/easy filler.

The generator may choose a lower ladder entry when duration cannot safely fit the nominal level.

### Tempo ladder (78–87% FTP)

1. 2 x 10 min, 4 min easy
2. 2 x 15 min, 4 min easy
3. 3 x 12 min, 4 min easy
4. 2 x 20 min, 5 min easy
5. 3 x 15 min, 4 min easy
6. 2 x 25 min, 5 min easy
7. 3 x 20 min, 5 min easy

### Sweet Spot ladder (88–94% FTP)

1. 3 x 8 min, 4 min easy
2. 3 x 10 min, 4 min easy
3. 3 x 12 min, 4 min easy
4. 2 x 20 min, 5 min easy
5. 3 x 15 min, 5 min easy
6. 2 x 25 min, 5 min easy
7. 3 x 20 min, 5 min easy

### Threshold ladder (95–102% FTP)

1. 4 x 6 min, 4 min easy
2. 3 x 8 min, 4 min easy
3. 4 x 8 min, 4 min easy
4. 3 x 10 min, 5 min easy
5. 3 x 12 min, 5 min easy
6. 2 x 20 min, 6 min easy
7. 3 x 15 min, 5 min easy

For the upper levels, bias targets toward 95–100% before increasing target percentage. Do not make level 7 simply “102% for longer”.

### VO2 Max ladder (108–118% FTP)

1. 5 x 2 min, 3 min easy
2. 6 x 2 min, 3 min easy
3. 5 x 3 min, 3 min easy
4. 6 x 3 min, 3 min easy
5. 5 x 4 min, 4 min easy
6. 4 x 5 min, 5 min easy
7. 5 x 5 min, 5 min easy

Target selection inside 108–118% should consider interval length:

- 2 min: 112–118%
- 3 min: 110–116%
- 4 min: 108–114%
- 5 min: 106–112%, but stay within the V1 VO2 intent and avoid making completion impossible merely to hit a zone label.

It is acceptable for the lower bound of 5-minute work to touch 106% because that matches the broader Z5 boundary.

### Over-under ladder

Represent each work block as repeating under/over segments, e.g. 2 minutes under + 1 minute over.

1. 2 x 9 min (2m under / 1m over x3), 5m easy
2. 3 x 9 min, 5m easy
3. 2 x 12 min (3m under / 1m over x3), 5m easy
4. 3 x 12 min, 5m easy
5. 2 x 16 min, 6m easy
6. 3 x 15 min, 6m easy
7. 2 x 20 min, 7m easy

Under: 88–94%.
Over: 102–108%.

## 15. Endurance workouts

Endurance does not need a 1–7 interval ladder.

Normal structure:

- progressive warm-up into Z2;
- long steady blocks at 60–72% FTP;
- optional subtle progressive/ramped blocks later in Build/Speciality, staying <=75%;
- simple cool-down.

When a new endurance workout is materialised, manually added, or explicitly selected with Change workout, randomly choose one of three profiles with equal probability:

- `sustained`: one sustained block at 65–72% FTP;
- `alternating`: alternating low (64–68%) and high (70–74%) endurance blocks;
- `undulating`: undulating ramps rising from the low band to the high band and falling back again.

Alternating and undulating profiles use an even number of roughly five-minute blocks, distributing the available main-set duration in 30-second increments. All profiles retain the usual warm-up, cool-down and exact total duration.

This is an explicit exception to deterministic workout selection. Persist the chosen variation and canonical steps; ordinary requests must not redraw structured or completed workouts. Forecasts use the sustained profile deterministically and actual metrics are recalculated on materialisation. Same shuffle cycles sustained → alternating → undulating → sustained; duration changes retain the chosen profile. Copying retains the original structure.

Do not turn Endurance into Tempo simply to increase TSS.

## 16. Recovery workouts

Default 45–55% FTP.

Keep simple and easy. A gentle ramp inside that band is fine. Avoid “activation” efforts that materially change the recovery purpose.

---

# Part D — Warm-up, cool-down and exact duration

## 17. Structured warm-ups

Warm-ups are workout-type specific.

### Recovery

- 5–8 min gentle ramp 40–50% → 50–55%.

### Endurance

- 8–12 min ramp 45–55% → 65–70%.

### Tempo / Sweet Spot

Preferred when duration allows:

1. 8–10 min ramp 45–55% → 70–75%.
2. 2 x 30 sec at 90–100% with 60 sec at 50–60%.
3. 2–3 min easy 50–60%.

### Threshold

Preferred:

1. 10 min ramp 45–55% → 75%.
2. 2–3 x 30 sec at 95–105% with 60 sec easy.
3. 3 min easy.

### VO2 / Over-under

Preferred:

1. 10–12 min ramp 45–55% → 75%.
2. 3 x 30 sec at 105–115% with 60 sec easy.
3. 3–5 min easy before main set.

For shorter 30–45 minute workouts, compress warm-up while preserving at least a sensible progressive start.

## 18. Cool-downs

Cool-downs are simpler than warm-ups.

Preferred:

- 5–10 minutes ramping from roughly 55–60% down to 40–50%.

Short sessions may use 5 minutes. Longer sessions can use 8–10.

## 19. Exact-duration fitting algorithm

Given requested duration D:

1. Select nominal main-set ladder entry for progression level.
2. Add preferred warm-up and cool-down.
3. If total < D:
   - first add easy Endurance/Z1-Z2 filler in logical locations;
   - then slightly lengthen warm-up/cool-down inside safe bounds;
   - never add extra hard intervals solely to consume spare minutes unless the next defined variation is appropriate for that progression level.
4. If total > D:
   - reduce optional easy filler;
   - compress warm-up/cool-down to their safe minimums;
   - if still too long, select the next lower main-set level/shorter variation.
5. Continue until exact sum = D.
6. The final adjustment can be a small easy block so every normal workout matches duration exactly.

Do not create sub-30-second junk steps simply to solve arithmetic. Prefer adjustments in 30-second or 1-minute units where possible.

---

# Part E — Workout variations and manual changes

## 20. Variation keys

`Shuffle: Same` must not be random.

Each subtype/level should have 2–4 deterministic structure variations with similar load, for example:

Threshold level 3 could include:

- 4 x 8 min / 4 min recovery;
- 3 x 10 min + 1 x 6 min / suitable recoveries;
- 2 x 16 min / 5 min recovery.

Variations should target roughly similar time-in-zone and estimated TSS/IF.

Store/derive a `variation_key` and rotate to the next key on each Same shuffle.

Variation keys describe the profile: recovery uses `steady` / `gentle_ramp`; intensity workouts use `standard` / `redistributed_recovery`; endurance uses `sustained` / `alternating` / `undulating`; openers use `activation`. Redistributed recovery moves 30 seconds from the first recovery to after the final effort. Legacy letter keys remain only in immutable completed history and the data migrations that rename uncompleted workouts.

Target tolerance for Same shuffle:

- duration: identical;
- TSS: preferably within ±5%;
- IF: preferably within ±0.03;
- subtype: identical.

If no alternate structure can satisfy tolerance, use the closest valid variation and show its metrics before applying.

## 21. Harder / Easier manual shuffle

Affects this workout only.

Preferred implementation:

- Harder: generate at progression level +1;
- Easier: generate at level -1;
- clamp 1..7;
- keep subtype and duration;
- use exact-duration fitter.

At a boundary level, use an alternate variation with modestly different time-in-zone/recovery rather than exceeding normal subtype power ranges.

Do not update plan progression bias from this action.

## 22. Shorter / Longer

- adjust exactly 15 minutes per action;
- minimum = 30 minutes;
- no maximum;
- regenerate structure to fit new duration;
- explicit Longer may exceed configured daily availability;
- this change applies only to that workout unless rider separately chooses a replan through Change Workout.

## 23. Change Workout

Rider chooses a new type and/or duration.

Generate a fresh valid workout at a progression level appropriate to current phase, then compare old/new load.

Treat as materially different if either:

- easy ↔ intensity intent changes; or
- estimated TSS changes by >=15%; or
- IF changes by >=0.08.

If material, offer optional near-term replan. Do not force it.

---

# Part F — Planned metrics and load control

## 24. Representative target for metrics

Because prescriptions are ranges, planned metrics need a deterministic representative power.

For steady step:

```text
representative_pct = (low_pct + high_pct) / 2
power = ftp * representative_pct / 100
```

For a ramp, linearly interpolate between the midpoint of the starting range and midpoint of the ending range across the step.

Use one-second samples internally for metrics. Workout sizes are small enough for V1; optimise later only if needed.

## 25. Estimated Normalized Power

Implement the conventional planned-power approximation:

1. Produce representative one-second power series.
2. Compute a 30-second rolling average power series.
3. Raise each rolling-average value to the fourth power.
4. Take the mean.
5. Take the fourth root.

For the initial <30 seconds, either:

- use a progressively sized rolling window until 30 samples exist; or
- use the first 30-second average once available.

Choose one approach, document it in code and lock it with tests. Since all V1 workouts are >=30 minutes, the edge has negligible plan-level effect.

The implemented calculator uses a progressively growing window for the first 29 samples, then a rolling 30-second window across step boundaries. Metrics specs lock this choice.

Call the result `estimated_np_watts` in code/UI where displayed.

## 26. IF, TSS and work

```text
IF  = estimated_np_watts / ftp
TSS = duration_hours * IF^2 * 100
work_kj = sum(power_watts_each_second) / 1000
```

Round for UI:

- IF: 2 decimals;
- TSS: nearest whole number or 1 decimal in detail view;
- work: nearest whole kJ.

Internally keep sufficient precision.

### Outline workouts >14 days

Weekly totals need future load estimates even before detailed steps are persisted.

For each outline prescription:

- generate an ephemeral representative workout definition in memory using the planned phase/progression level;
- calculate forecast metrics;
- persist/store estimated TSS/IF/work on the outline record if useful;
- do **not** persist its steps until it enters the 14-day horizon.

When materialised, recalculate metrics from the actual chosen variation. Small changes from forecast are acceptable and should roll into weekly totals.

## 27. Weekly TSS growth cap

V1 default hard-week progression cap:

- no automatically generated hard week should exceed the most recent comparable hard week's planned TSS by more than **8%**.

This is a product heuristic, not a claim that 8% is a universal physiological threshold.

### Comparable week

Do not compare against:

- partial first week;
- recovery week;
- taper week;
- time-off week;
- illness/re-entry week.

After a recovery week, compare the next hard week against the hard week immediately before recovery.

### Enforcement order

When a generated week exceeds cap:

1. lower progression level of broad/specific interval workouts, highest-load session first;
2. select lower-load valid variations;
3. lower work-target location within the allowed target range;
4. for broad Intervals only, choose a less demanding valid subtype if compatible with goal/phase;
5. add easy filler rather than hard work where duration must be preserved;
6. if still impossible because the rider has explicitly expanded availability, use the lowest valid generated load and show a non-blocking warning that the requested schedule itself creates a larger load jump.

Do not silently shorten normal hard-week availability merely to satisfy the cap. Recovery/taper/re-entry are separate exceptions.

Manual one-off Harder/Longer edits may make the week exceed this cap. Show the resulting weekly load but do not block the rider.

---

# Part G — Feedback and adaptation

## 28. Expected RPE bands

Use these only as adaptation heuristics:

| Subtype | Expected RPE |
|---|---:|
| Recovery | 1–3 |
| Endurance | 2–4 |
| Tempo | 4–6 |
| Sweet Spot | 5–7 |
| Threshold | 7–9 |
| VO2 Max | 8–10 |
| Over-under | 7–9 |

## 29. Single-workout feedback evaluation

Feedback fields:

- RPE 1–10;
- completion quality.

### Completed as planned

- RPE inside expected band: no immediate adaptation; follow planned progression.
- RPE at least 2 points below expected lower bound on an intensity workout: propose making the next comparable detailed workout one progression level harder, subject to TSS cap.
- RPE above expected upper bound: propose one-level reduction to next comparable detailed workout.

For Recovery/Endurance, unusually low RPE is not a reason to turn the next session into intensity. Normally do nothing. Unusually high RPE may justify lowering the next comparable easy session's target/structure.

### Struggled but completed

Propose reducing the next comparable intensity workout by one progression level. If another hard workout occurs within 48 hours and is broad `Intervals`, the proposal may also choose a less demanding subtype or lower level while keeping the day an intensity day.

### Could not complete

Propose:

- next comparable intensity workout: reduce by two levels (minimum 1);
- if there is another intensity workout within 48 hours: reduce it one level as well;
- never add volume elsewhere to “make up” failed work.

All of the above are proposals, not automatic changes.

## 30. What “comparable” means

Priority:

1. same subtype;
2. same broad intensity family (Tempo/Sweet Spot/Threshold or VO2/Over-under as appropriate);
3. next broad `Intervals` session if subtype was engine-selected.

Do not modify Endurance because a Threshold workout was hard unless the proposed adaptation is explicitly reducing overall near-term load after a severe failure pattern.

## 31. Near-term adaptation scope

Single-workout feedback may alter only workouts in the next 14 days.

Never alter:

- completed workouts;
- rider's availability template;
- target event;
- plan goal/discipline;
- phase dates merely because of one hard session.

## 32. Repeated feedback and long-term bias

Track recent accepted feedback state per intensity family/subtype in `TrainingPlan#progression_state`.

A clear pattern is:

- at least 2 of the last 3 comparable completed intensity workouts were “too hard” (struggled/could-not-complete or above expected RPE); or
- at least 2 of the last 3 were clearly “too easy” (completed as planned and >=2 RPE points below expected lower bound).

When a pattern exists, include a long-term progression-bias change in the adaptation proposal:

- too hard: bias -1;
- too easy: bias +1;
- clamp total bias -2..+2.

This bias affects future workout generation when outline workouts later enter the 14-day window. It does not require rewriting the whole distant calendar.

## 33. Late completion rule

If an older workout is completed late:

- save its feedback normally;
- only offer a new adaptation if the next upcoming workout has not already been completed;
- do not retroactively regenerate anything already completed since the old workout date.

---

# Part H — Missed workouts, schedule changes and time off

## 34. Missed workout: leave unchanged

- retain the workout on its original date with `status = missed`, as required by MIS-001;
- do not add compensatory work;
- preserve future prescriptions.

## 35. Missed workout: move

- rider chooses an empty date;
- preserve structure if moving within a short near-term window and phase context is still sensible;
- if moved across a phase boundary or by >7 days, regenerate at the destination's phase/progression context while keeping requested subtype/duration unless rider previews otherwise;
- recheck weekly TSS and warnings;
- one workout per day.

## 36. Missed workout: replan

Near-term only, normally 7–14 days.

Goals:

- do not “repay training debt” by stacking extra intensity;
- preserve rider-selected intensity/endurance days;
- restore sensible separation/progression;
- drop the missed stimulus if no suitable slot exists;
- respect TSS growth cap.

## 37. Availability change — one week

Create a bounded availability template for that Monday–Sunday week.

Regenerate future/uncompleted prescriptions in the affected week and any immediately dependent near-term progression if needed.

Completed workouts are untouched.

## 38. Availability change — from date onward

Close the previous template and create a new effective template.

Recreate future prescriptions from effective date through plan end at high level, preserving:

- plan phases;
- target event/taper;
- time off;
- completed workouts;
- accepted progression bias.

Materialise the next 14 days again where needed.

## 39. Time off

No normal workouts during time-off dates.

Do not automatically extend plan end date in V1. Event date is always fixed; non-event plans also keep their original end date for predictable behaviour.

### Holiday / Event / Other

After the break:

- resume from approximately the progression level reached immediately before the break rather than jumping to the calendar's originally projected higher level;
- continue progressing from there;
- accept that a plan may finish at a slightly lower progression level after a long break.

### Illness / Recovery

After time off, rider chooses `return_ramp_days`.

Build a re-entry curve over that period.

Suggested deterministic stages based on percentage of ramp elapsed:

- first 25%: Recovery/low Endurance only, 45–60%; 50–70% of normal scheduled duration;
- 25–50%: Endurance, 55–68%; 60–80% normal duration;
- 50–75%: Endurance + optional low Tempo on an intensity day; 70–90% duration;
- final 25%: reintroduce the scheduled subtype at progression level 1–2 below pre-break level, up to normal duration;
- after ramp: resume normal schedule, progressing from the reduced level rather than instantly jumping to the old calendar projection.

If the rider selects a very short ramp (e.g. 2–3 days), collapse stages proportionally; do not schedule multiple workouts on the same day.

The user explicitly chooses ramp length, but the engine chooses the stepped content.

---

# Part I — FTP-test placement

## 40. When to schedule assessments

Do not schedule routine FTP tests in plans shorter than 6 weeks unless a natural major phase transition occurs and there is enough time for the new FTP to matter.

For longer plans:

- target reassessment roughly every 4–6 weeks;
- use 5 weeks as the ideal spacing;
- move the date within the 4–6 week window to a better training location.

## 41. Candidate ranking

Prefer, in order:

1. first configured intensity day after a recovery week;
2. first configured intensity day at the start of Build or Speciality;
3. an intensity day preceded by rest/recovery;
4. another normal workout day if no intensity day exists.

Rules:

- replace that day's normal workout;
- do not schedule during time off or return-to-training ramp;
- do not schedule within 14 days of the target event;
- avoid placing two FTP tests <28 days apart or >42 days apart when a valid slot exists;
- do not invent a test protocol;
- no planned TSS/IF/work for FTP Test because execution protocol is unknown.

## 42. FTP Test calendar behaviour

Display `FTP Test` as a special workout replacement.

Detail text should say, in effect:

- perform the rider's preferred FTP assessment;
- then update FTP in Settings.

A simple `Test done` status action may be implemented without RPE/completion-quality feedback. Updating FTP remains a Settings operation in V1.

---

# Part J — Taper and opener

## 43. Taper goals

Taper should reduce accumulated fatigue while preserving familiarity with intensity.

V1 generated-load target:

- roughly 40–60% lower TSS than a comparable peak hard week by event week, depending on taper length;
- reduce volume more than intensity;
- retain brief intensity touches but sharply reduce hard time-in-zone.

Taper may override normal template.

## 44. Taper implementation

For a 7-day taper:

- early week: one reduced intensity session, roughly 50–70% of its normal hard time-in-zone;
- remaining rides mostly easy Endurance/Recovery and potentially shorter than normal availability;
- day before event: opener;
- no hard workout designed to create residual fatigue in final 48 hours.

For 10–14 day taper:

- first taper week: ~70–80% of normal peak load;
- event week: ~40–60% of normal peak load before the event;
- retain brief intensity exposures.

## 45. Opener workout

Place one day before the event unless there is a specific calendar conflict created by time off; the event goal takes priority over the normal weekly template.

Default duration:

- 30–45 minutes;
- use 30 min for shorter plans/low availability;
- 40–45 min if normal schedule supports it.

Example structure to be fitted exactly:

1. 10 min ramp 45–55% → 70%.
2. 3 x 1 min at 100–108%, 2 min at 50–60%.
3. 3 x 30 sec at 108–118%, 90 sec easy.
4. Remaining time easy 50–65%.
5. 5 min cool-down.

Purpose: activation, not training stress. Name: `Event Opener` (descriptive special case).

---

# Part K — Calendar materialisation

## 46. 14-day window

Detailed horizon is:

```ruby
Date.current..(Date.current + 13.days)
```

A planned executable workout in that range must be structured. Completed and missed records are not materialised. Explicit Add and Copy actions can create structured workouts outside this automatic horizon; moving an already structured workout can also retain its steps outside it. Explicitly opening or completing a due/overdue executable outline materialises that one workout using its saved prescription context, current FTP and accepted bias, with the same reduced-load ceilings and weekly cap. Other outlines remain untouched.

High-level outline outside range stores:

- date;
- phase;
- intent/subtype (where already selected);
- duration;
- purpose;
- forecast load metrics.

## 47. Materialisation inputs

When an outline enters the horizon, use the latest:

- current FTP for watts/metric display;
- accepted progression bias;
- preceding feedback state;
- schedule/time-off state;
- engine version attached to plan.

Do not reinterpret goal/discipline/phase structure.

## 48. Stability rule

Once a detailed workout is generated, keep its structure stable unless one of these explicit events occurs:

- Shuffle;
- Change workout;
- accepted feedback adaptation;
- missed-workout replan;
- schedule change affecting it;
- time-off replan affecting it;
- taper/FTP-test plan operation that explicitly rewrites it.

A mere horizon roll or FTP change is not a reason to change percentage structure.

---

# Part L — Descriptive names and explanations

## 49. Workout names

Use structure-first descriptive names.

Examples:

- `Threshold 3x12`
- `VO2 Max 5x4`
- `Sweet Spot 2x20`
- `Tempo 3x15`
- `Over-Unders 3x12`
- `Endurance 90 min`
- `Recovery 45 min`
- `Event Opener`
- `FTP Test`

Do not generate arbitrary branded names.

## 50. “Why this workout?”

Generate from rule metadata, not AI.

Examples:

- `Build phase threshold session. Progresses sustained time near FTP from your previous threshold level.`
- `Speciality VO2 session for MTB. Develops repeated aerobic-power efforts while keeping your Saturday intensity day.`
- `Recovery-week session. Load is reduced to absorb the previous hard block.`

Store rule/reason codes if helpful; render human text from them.

---

# Part M — Test matrix for the engine

## 51. Required unit/property tests

At minimum, test:

### Zone/target maths

- every subtype stays inside allowed FTP bands;
- target low <= target high;
- no V1 generated work >120% FTP.

### Duration

For each subtype, levels 1–7 and representative durations 30/45/60/75/90/120 minutes:

- sum(step durations) == requested duration;
- no zero/negative steps;
- minimum warm-up/cool-down rules hold where applicable.

### Plan phases

- 4-week minimum plans;
- 1/3/6 month presets;
- Base included/skipped;
- event taper 7/14 day scenarios;
- phase dates do not overlap and stay inside plan.

### Recovery cycle

- N hard weeks then recovery;
- alignment near phase transition;
- recovery TSS reduction;
- no recovery week inside taper.

### Interval selection

- broad Intervals deterministic cycle by goal/phase/discipline;
- specific subtype never unexpectedly replaced in normal weeks.

### Load cap

- generated hard-week growth <=8% vs comparable reference when feasible;
- recovery weeks excluded from reference;
- next hard week after recovery compares to pre-recovery hard week;
- manual Harder/Longer can exceed cap without mutating future progression.

### Feedback

- normal RPE produces no proposal;
- too easy/hard thresholds;
- struggled/could-not-complete reductions;
- proposal not applied until accepted;
- repeated 2-of-3 pattern changes long-term bias only on acceptance;
- late feedback rule.

### FTP change

- planned watts update;
- percentage structure unchanged;
- completed snapshot unchanged.

### Horizon

- automatic materialisation persists steps only in the next 14 days; explicit Add/Copy and retained moved structures are exceptions;
- day entering horizon materialises;
- existing structured workout remains stable.

### Time off

- no workouts in range;
- holiday resumes from pre-break progression level;
- illness/recovery uses selected ramp duration;
- no completed workouts are changed.

### Taper/opener

- event fixed;
- opener day before event;
- opener <=45 min and low load;
- taper overrides normal template without changing event.

### Metrics

Use hand-checkable constant-power fixtures:

- 60 min at 100% FTP -> IF ~1.00, TSS ~100;
- 60 min at 50% FTP -> IF ~0.50, TSS ~25;
- work kJ matches watts x seconds / 1000;
- range midpoint and ramp interpolation rules are deterministic.

These tests matter more than controller/view coverage for the core product.
