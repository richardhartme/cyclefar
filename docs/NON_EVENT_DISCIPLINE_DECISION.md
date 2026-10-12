# CYF-86 — Discipline in non-event plans

Decision agreed with the product owner on 12 October 2026. Issue: [CYF-86](https://richardhartme.atlassian.net/browse/CYF-86), under [CYF-84](https://richardhartme.atlassian.net/browse/CYF-84).

## Decision

Omit discipline from setup for General Fitness, Increase FTP, Improve Endurance and Improve Climbing. Keep their existing deterministic goal/phase training rules. Discipline remains a required, effective input for Prepare for an Event.

An ineffective choice adds work and implies training customisation that the engine does not provide. Adding discipline effects would require separately reviewed training rules for every goal/phase and their interaction with explicit weekly intents. This decision introduces no new cycles, power percentages, progression ladders or load constants.

## Evidence and resolved conflict

PLN-010 previously required discipline for every plan. PLN-021 and PRODUCT.md described increasing discipline specificity without limiting it to event plans; TRAINING_ENGINE.md §10 had the same ambiguity. The precise non-event cycles in §11 already depend only on goal and phase.

`Planning::Rules::INTERVAL_CYCLES` defines those non-event cycles. `IntervalSelector#call` consults `EVENT_DISCIPLINE_CYCLES` only for the event goal in Build/Speciality. Event Base uses the generic event cycle. `LoadReduction#compatible_lower_subtypes` uses the same distinction. `Workouts::Generator` validates and carries discipline as context, but it does not use it to change canonical steps, names, purpose or progression. Phase allocation, recovery and load limits do not vary by non-event discipline.

The requirements and product wording now match those rules: non-event plans are goal/phase-specific; event Build/Speciality broad Intervals are discipline-specific. Explicit weekly subtypes bypass automatic subtype selection, subject to the existing recovery, taper, time-off and load rules. Endurance/Recovery, rider-selected days and normal durations gain no discipline-dependent behaviour.

## Persistence and compatibility policy

These are requirements for the follow-on implementation, not changes delivered by CYF-86:

- New non-event configurations resolve `training_discipline` to `road` on the server and persist `TrainingPlan.discipline = road`. Keep the existing required enum, database constraint and generator contract. This is an internal compatibility value, not a rider-selected discipline or evidence of Road-specific training. Put the default in `Planning::Rules`.
- Missing, blank, invalid or stale submitted non-event `discipline` values neither affect generation nor block preview/confirmation. Inactive event discipline does not affect non-event training. Apply the policy to session drafts created before the form change as well as new submissions.
- Event configurations still require a valid Event discipline. Start a fresh event selector at Road; preserve its entered value across goal toggles, validation errors and Back to edit. Only active event mode validates it. Do not infer it from stale non-event input, including old drafts; an explicitly invalid active choice is rejected.
- Keep every existing active/archived plan's stored discipline. Do not backfill it to Road, clear it, migrate workouts or change `ExistingPlanConfiguration` to use the new-form default. Replanning/materialisation keep reading the existing plan context; non-event results remain independent of that value. Preserve completed structures, FTP snapshots, steps and feedback.
- Omit discipline from non-event configuration summaries, preview labels and the calendar plan header, including for existing non-event plans. Never display the internal Road default as a selected training input. Event summaries keep showing the effective discipline; legacy event-label mismatches retain CYF-85's compatibility policy.
- Remove generic public copy that asks every rider to choose a discipline. Explain that non-event broad Intervals use goal and phase, while explicit weekly subtypes keep their intent. Changing a confirmed goal or event discipline still requires a new plan.

## Delivery boundary and follow-on work

CYF-86 delivers this decision, consistent specifications and regression coverage of the retained training behaviour. It changes no runtime form, validation, presenter, schema or engine behaviour. The current form still requires non-event discipline until the following work is implemented together; it must not claim this input tailors training.

Follow-on implementation under CYF-84 must:

1. Remove the non-event controls from `training_plans/new`, adapt the existing `plan-discipline` Stimulus controller to event-only visibility, and preserve the event selection through editing. Keep training/defaulting/validation on the server.
2. Update `PlanConfiguration` and its session-draft handling to implement the default/ignored-input policy above. Keep `PlanCreator` persisting the effective value and `ExistingPlanConfiguration` preserving confirmed values.
3. Update preview and calendar summaries plus public setup copy. [CYF-90](https://richardhartme.atlassian.net/browse/CYF-90)'s configuration summary must follow this policy; that issue alone does not cover the form and server changes.
4. Replace the superseded CYF-85 non-event-required validation expectations when implementing the new contract, retaining its event precedence and legacy preservation coverage. Update current-implementation notes in the specifications at delivery.

Required follow-on coverage:

- All four non-event goals accept absent/blank/invalid/stale discipline, preview identically, and confirm with the internal Road value; inactive event choices cannot influence training or block submission.
- Setup/preview/calendar omit non-event discipline for new and existing plans. Event setup requires one selector; goal toggles, errors, preview refresh and Back to edit preserve it. Legacy drafts obey the same defaulting and active-validation policy.
- Preview and confirmation agree on effective event discipline; existing event Build/Speciality cycles, generic Base and explicit-intent rules remain covered.
- Existing non-Road non-event plans retain their value through availability/time-off replanning and horizon materialisation. Completed history remains byte-for-byte unchanged.

CYF-86's preview regression matrix covers all four non-event goals and all four stored disciplines through Base/Build/Speciality, including broad Intervals, explicit intensity intents, Endurance/Recovery, forecasts, weekly totals and load warnings. Existing event and immutability specs remain part of the required full-suite gate.
