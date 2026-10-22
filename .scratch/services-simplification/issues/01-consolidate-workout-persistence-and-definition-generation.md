# Consolidate workout persistence and definition generation

Status: resolved
Blocked by: none

Covers review items 1 and 2 of the `app/services` complexity review.

## Problem

Eight services copy the same block that assigns a generated workout's attributes, metrics and steps: `Creator`, `Mover`, `ManualEditor`, `WorkoutBuilder`, `FuturePrescriber`, `PlanCreator`, `FtpRecalculator` and `Copier`. Seven services build `Generator` or `OpenerGenerator` by hand, each with its own opener branching: `PlanBuilder`, `FuturePrescriber`, `WorkoutBuilder`, `Mover`, `ManualEditor`, `Creator` and `WeeklyLoadReview`.

## Scope

- Add one persistence path, either `Workouts::Applier` or `PlannedWorkout#apply_definition(definition, metrics)`. It owns the attributes, the steps and the `generation_context` keys (`baseline_level`, `generated_level`, `generated_tss`, `load_adjustments`). `PlannedWorkout::METRICS` already exists and is partly used.
- Add a `Workouts::DefinitionFactory` that builds a definition from a workout or prescription plus the plan.
- Move every existing callsite onto both.
- Consider splitting `Generator#call` into generate, adjust and describe steps.

## Acceptance criteria

- [ ] No service assigns the `estimated_*` attributes or builds steps from `step.to_h` outside the shared path.
- [ ] No service branches on `opener?` to choose a generator.
- [ ] Completed-workout immutability is unchanged, with specs proving it.
- [ ] `bundle exec rspec` and `bin/rails zeitwerk:check` pass.

## Comments

Implemented in a873072 and merged (follow-up lint fix 8853c5a).
