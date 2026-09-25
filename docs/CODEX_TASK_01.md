# CycleFar Codex Task 01 — Bootstrap + Core Persistence

Historical bootstrap prompt, completed in September 2026. Retained for provenance; do not execute it against the existing application. Read [STATUS.md](STATUS.md) for current work. Specification paths below are relative to `docs/`; `AGENTS.md` is at the repository root.

## Prompt

Read the complete specification, starting with `AGENTS.md`, then `PRODUCT.md`, `REQUIREMENTS.md`, `DATA_MODEL.md`, `ARCHITECTURE.md` and `IMPLEMENTATION_PLAN.md`.

Implement **Milestones 0 and 1 only** from `IMPLEMENTATION_PLAN.md`.

The deliverable for this task is:

1. A locally runnable Rails application named **CycleFar** (`cycle_far` project identifier / `CycleFar` application module) using Ruby 4.0.6, Rails 8.1.3.1, PostgreSQL, Hotwire/Turbo, Stimulus and Tailwind CSS.
2. RSpec and FactoryBot configured as the test framework/test-data factory.
3. The core database models and migrations described in `DATA_MODEL.md`, including database-level constraints for:
   - at most one active training plan;
   - at most one cycling workout per plan/date where applicable.
4. A singleton Rider Settings/Profile implementation with:
   - current FTP;
   - encrypted Intervals.icu API key;
   - lightweight FTP history creation when FTP changes.
5. A simple Settings page that can edit FTP and the API key.
6. Model/service specs for the invariants implemented in this milestone.
7. A minimal application layout/navigation branded **CycleFar**, sufficient to reach Settings and the root page.
8. The root page should show the no-plan `Create training plan` call-to-action, but **do not build plan generation or the configuration form yet**.

Important constraints:

- Do not implement the workout-generation engine yet.
- Do not implement Intervals.icu network calls yet.
- Do not add authentication, React, Redis, Sidekiq or deployment infrastructure.
- Keep training/replanning logic out of Active Record callbacks.
- API key must not appear in logs.
- Prefer conventional Rails code and explicit database constraints.

Before finishing:

```bash
bundle exec rspec
bin/rails zeitwerk:check
```

Fix failures rather than leaving them for a later milestone.

At the end, report:

- what was implemented;
- any small specification interpretation you had to make;
- test count/result;
- migrations/models/routes added;
- what remains explicitly deferred to Milestone 2.
