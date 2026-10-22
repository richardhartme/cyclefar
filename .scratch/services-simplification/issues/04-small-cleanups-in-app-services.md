# Small cleanups in app/services

Status: needs-triage
Blocked by: 02

Covers the "small and mechanical" list of the `app/services` complexity review. Can run in parallel with 03.

## Scope

- Move the duplicated `reduced_duration` (in `PlanBuilder` and `FuturePrescriber`) into `Training::Rules` or a helper.
- Add `TrainingPlan#intensity_bias` to replace six copies of `progression_state.fetch("intensity_bias", 0).to_i`.
- Remove the 25 `require_relative` lines that Zeitwerk makes unnecessary.
- Normalise string and symbol `kind` usage, and remove the manual `.to_s.dup.freeze` noise in `Prescription#initialize`.
- Move the magic numbers into `Planning::Rules` or `Training::Rules`: the 13/14-day horizon, the 15-minute shorter/longer step, the 0.15 and 0.08 material-change thresholds, the return-stage cap of 3 and the divisor of 4.
- Have `WeeklyLoadReview#estimated_tss` and `WorkoutBuilder#candidate_for` use the definition factory from 01 instead of their own generate-then-measure fallbacks.

## Acceptance criteria

- [ ] No behaviour change.
- [ ] `bundle exec rspec` and `bin/rails zeitwerk:check` pass.

## Comments
