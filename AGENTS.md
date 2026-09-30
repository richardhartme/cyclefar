# AGENTS.md — CycleFar Codex Implementation Instructions

## Mission

Build **CycleFar**, the V1 cycling training planner described in this repository. Favour correctness, deterministic behaviour and maintainable Rails code over cleverness.

## Read before coding

Read these files in order:

1. `PRODUCT.md`
2. `REQUIREMENTS.md`
3. `TRAINING_ENGINE.md`
4. `DATA_MODEL.md`
5. `ARCHITECTURE.md`
6. `UX.md`
7. `INTERVALS_ICU.md`

If documents appear to conflict, use this precedence:

1. `REQUIREMENTS.md`
2. `TRAINING_ENGINE.md` for training behaviour
3. `PRODUCT.md`
4. `DATA_MODEL.md` / `ARCHITECTURE.md`
5. `UX.md`

Do not silently invent major product behaviour. If a small implementation detail is unspecified, choose the simplest conventional Rails solution and record the decision in code comments only when it is non-obvious.

## Product identity

- User-facing product name: **CycleFar**.
- Rails application/project name: `cycle_far`; Ruby application module: `CycleFar`.
- Future owned domain: `cyclefar.com`; do not add deployment/configuration for it in V1.
- Keep the CycleFar brand out of core model/table names. Use domain names such as `TrainingPlan` and `PlannedWorkout`.
- For integration ownership identifiers, use a stable `cyclefar-` namespace.

## Stack

Use:

- Ruby 4.0.6 initially
- Rails 8.1.3.1 initially
- PostgreSQL
- Hotwire/Turbo
- Stimulus
- Tailwind CSS
- RSpec
- FactoryBot

Useful test-only/support gems are allowed when justified, e.g.:

- `rspec-rails`
- `factory_bot_rails`
- `webmock` for Intervals.icu client specs
- `timecop` only if Rails time helpers are insufficient; prefer ActiveSupport time helpers first

Do not add React/Vue/Svelte, a CSS component framework, GraphQL, Sidekiq, Redis, Devise or an LLM SDK in V1.

## Rails conventions

- Prefer RESTful resources and explicit service objects.
- Keep controllers thin.
- Keep Active Record callbacks minimal; do not hide plan generation/replanning in callbacks.
- Avoid “god” models.
- Use database constraints/indexes in addition to model validations for important invariants.
- Use enums deliberately and test them.
- Use `date` for training schedule concepts.
- Use transactions for multi-record plan mutations.

## Training-engine rules

The engine is a first-class domain component.

- Training decisions must be deterministic.
- No random or time-dependent workout choice beyond explicit calendar date inputs, except the user-requested initial endurance profile selection (WKO-009). Save that selection; previews and regeneration with an explicit variation remain deterministic.
- Keep rule constants grouped/versioned under an engine namespace, e.g. `Training::V1` or `Planning::V1`.
- Do not bury percentages or progression thresholds across controllers/models.
- Pure calculations should be pure Ruby objects with fast unit specs.
- Persist `engine_version` on plans.
- Do not change V1 constants just to make a failing feature spec pass; fix the implementation or deliberately update the specification.

## Canonical workout representation

The Rails workout/step model is canonical.

Never make any of these the source of truth:

- Intervals.icu text
- rendered HTML
- SVG graph points
- absolute watt targets for future workouts

Canonical targets are percentages of FTP. Absolute watts are derived for future workouts and snapshotted on completion.

## Completed-workout immutability

Once a workout is completed:

- do not mutate structure;
- do not recalculate its historical watts when FTP changes;
- do not let replanning/schedule changes/time off rewrite it.

Write model/service specs proving this invariant before building later replanning features.

## UI guidance

- Desktop-first.
- Main screen after plan creation is the continuous calendar.
- Use Turbo Frames/Streams for modal and in-place updates.
- Use Stimulus only for interaction/presentation; training logic stays server-side.
- Workout mini graphs can be inline SVG.
- Prefer accessible native controls.
- No drag-and-drop in V1.
- No calendar filters in V1.

## Intervals.icu integration

- Keep HTTP code isolated under `IntervalsIcu`.
- Never make real network calls in specs.
- Never log API keys.
- Use stable CycleFar-owned `external_id` values prefixed with `cyclefar-`.
- The sync button reconciles only CycleFar-owned events.
- Never delete or overwrite unrelated calendar events.
- Verify the current external API contract while implementing the adapter; if it has changed, adapt the adapter rather than the domain model.

## Testing standard

Every behaviour in `REQUIREMENTS.md` with an ID should have meaningful automated coverage at the most appropriate level.

Priorities:

1. training-engine unit specs;
2. model invariant specs;
3. service/replanning specs;
4. Intervals.icu adapter specs;
5. request/system specs for critical user flows.

Critical system/request flows:

- create plan -> preview -> confirm -> calendar;
- open structured workout;
- shuffle/change/move;
- complete -> feedback -> adaptation proposal -> accept/reject;
- overdue -> missed resolution;
- change availability;
- add illness time off + return ramp;
- update FTP and verify completed/future behaviour;
- manual Intervals.icu sync with stubbed API.

Avoid brittle tests that assert Tailwind class strings. Test semantic content/actions.

## Quality gates

Before declaring a milestone complete:

```bash
bundle exec rspec
bin/rails zeitwerk:check
```

Also run any configured lint/security tools if added to the project.

For training-engine work, add explicit specs for edge cases before moving to the next milestone.

## Seed/demo data

Provide a development seed path that can create a realistic sample plan for visual testing, but do not make production logic depend on seeds.

A useful sample:

- FTP 260 W
- Increase FTP
- Road
- 12 weeks
- Tue 60 min Intervals
- Thu 90 min Endurance
- Sat 60 min Intervals
- Sun 120 min Endurance
- 3 hard weeks / 1 recovery week

## Do not implement yet

Rails-generated authentication has already been added. Do not extend it into:

- self-service registration or multiple riders;
- automatic ride imports;
- trainer control;
- notifications;
- mobile redesign;
- AI coaching;
- custom zones;
- multiple events/plans;
- activity/history analytics;
- drag-and-drop.

## Working style

Keep commits/changes small enough that the training rules can be reviewed independently from UI code.

At the start of a task, read docs/STATUS.md. Only work on the current milestone unless explicitly instructed otherwise. When a milestone is complete and all tests pass, update docs/STATUS.md to mark it complete and set the next milestone as current.
