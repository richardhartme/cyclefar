# Unify time-off, recovery-week and return-ramp logic

Status: needs-triage
Blocked by: 01

Covers review items 4 and 5 of the `app/services` complexity review. Blocked by 01 because `Mover` is rewritten in both.

## Problem

Several services re-derive the same time-off logic:

- `Mover#recovery_week?` duplicates `RecoverySchedule`.
- `Mover#return_stage` duplicates `ReturnRamp#stage_on`.
- The return-ramp date test appears in `LoadContext#reduced?` and `FuturePrescriber#return_ramp_period_for`.
- The period/week overlap test appears in `LoadContext#comparable_week?` and `ProposalFreshness#relevant_period?`.
- Availability-template selection is duplicated in `MaterialChangeReplanner#dates_by_template` and `ProposalFreshness#availability_context`. `availability_for_week.rb` likely does the same and needs checking.

## Scope

- Add a shared `Planning::TimeOffTimeline`, or methods on `TimeOffPeriod`, with `blocked?(date)`, `ramp_period_for(date)`, `latest_completed_before(date)` and `overlaps_week?(week_start)`.
- Add a single `AvailabilityTemplate.for_date` lookup.
- Make `Mover` use `RecoverySchedule` and `ReturnRamp` directly.

## Acceptance criteria

- [ ] Each concept is defined in one place.
- [ ] Existing training-engine and replanning specs pass unchanged.
- [ ] New unit specs cover the shared timeline.
- [ ] `bundle exec rspec` and `bin/rails zeitwerk:check` pass.

## Comments
