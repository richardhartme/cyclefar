# Break up PlanBuilder, ManualEditor and ProposalFreshness

Status: needs-triage
Blocked by: 02

Covers review items 3, 6, 7, 8 and 9 of the `app/services` complexity review. This could be split into one ticket per class if preferred.

## Scope

- **`PlanBuilder` (428 lines):**
  - Extract `Prescription`, `Week` and `Preview` into their own files.
  - Extract taper logic (`taper_intensity?`, `early_long_taper?`, `taper_source_phase`, `taper_load`) into `Planning::TaperPlan`. Rewrite the nested `while` loops in `taper_load`, which mutate `prescriptions` and `stage` in parallel by index, over a pure collection.
  - Memoise `taper_phase`, which is currently recomputed four times.
  - Move the opener duration constants into `Planning::Rules`.
- **`ManualEditor`:** one small object per action (same, shorter, longer, change, adapt) instead of the 4-tuple `case`. Move `Snapshot`, `Result` and `Preview` out. Define the intensity-subtype set once in `Training::Rules`; it is currently duplicated here, in `PlanBuilder#intensity?` and inline at `plan_builder.rb:195`.
- **`ProposalFreshness`:** split the verdict from a `PlanFingerprint`. Parse `payload["changes"]` once, for example via a `proposal.changes` accessor that raises `Unavailable` on bad shape. Remove the repeated `reload` calls.
- **`PlanConfiguration`:** use ActiveModel `attribute` types for coercion, collapse the repeated type-or-range validation pairs in `event_is_valid` into one helper, and split `ends_on` into two private methods. Consider resolving the `plan_length` UI shorthand outside the model.
- **Load limiting:** share one `Planning::Candidate` and `LoadReduction` pipeline across `PlanBuilder`, `WorkoutBuilder` and `Mover`, replacing `Mover::Candidate` and `WorkoutBuilder::Candidate`.

## Acceptance criteria

- [ ] Behaviour is unchanged. Engine output is identical for the sample plan and the existing taper specs.
- [ ] No class in this scope is over roughly 200 lines.
- [ ] Each extraction lands as a separate commit.
- [ ] `bundle exec rspec` and `bin/rails zeitwerk:check` pass.

## Comments
