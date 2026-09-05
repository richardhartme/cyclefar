# CycleFar Build Status

Current milestone: 4 — Persist plan + continuous calendar
Status: Not started; awaiting the next implementation task

## Milestones

Numbering follows `IMPLEMENTATION_PLAN.md` and `CODEX_TASK_01.md`.

- [x] Milestone 0 — Bootstrap and guardrails
- [x] Milestone 1 — Settings and core persistence
- [x] Milestone 2 — Pure workout engine
- [x] Milestone 3 — Plan preview engine
- [ ] Milestone 4 — Persist plan + continuous calendar
- [ ] Milestone 5 — Workout detail and manual editing
- [ ] Milestone 6 — Completion, overdue and adaptations
- [ ] Milestone 7 — Missed workouts and schedule changes
- [ ] Milestone 8 — Time off and return to training
- [ ] Milestone 9 — FTP lifecycle
- [ ] Milestone 10 — Intervals.icu sync
- [ ] Milestone 11 — Polish and hardening

## Current work

Milestone 3 is complete. No later implementation milestone has started.

## Last completed

2026-09-05: Milestones 0 and 1 implemented locally (not committed by Codex).

- Ruby 4.0.6 / Rails 8.1.3.1 pinned and verified.
- All 13 core models, two migrations, database constraints and completed-history guards.
- Singleton Settings, encrypted API key, transactional FTP history.
- CycleFar navigation, home CTA and plan-creation placeholder.
- RSpec / FactoryBot, local setup instructions and CI test configuration.
- `bundle exec rspec`: 81 examples, 0 failures.
- `bin/rails zeitwerk:check`: passed.
- RuboCop: 57 files, no offenses.
- Brakeman: no warnings; gem and importmap audits: no vulnerabilities.
- `bin/setup --skip-server`, Tailwind build and development encryption check: passed.

2026-09-05: Milestone 2 implemented locally (not committed by Codex).

- Added a versioned, deterministic pure-Ruby workout engine for all seven workout subtypes.
- Added exact-duration fitting, progression ladders, warm-ups/cool-downs, deterministic variants, FTP-independent profiles and one-second metrics.
- Added 993 focused engine examples covering duration, progression, target bounds, metrics and edge cases.
- `bundle exec rspec`: 1081 examples, 0 failures.
- `bin/rails zeitwerk:check`: passed.
- RuboCop: 79 files, no offenses.

2026-09-05: Milestone 3 implemented locally (not committed by Codex).

- Added a validated plan-configuration form and an in-memory plan preview screen.
- Added deterministic phase allocation, recovery overlays, interval selection, taper/opener and FTP-test placement, forecast metrics and weekly load-cap enforcement.
- Added plan-preview unit and request specs covering goals, durations, phases, recovery modes, taper, FTP tests, load limits and non-persistence.
- `bundle exec rspec`: 1094 examples, 0 failures.
- `bin/rails zeitwerk:check`: passed.
- RuboCop: 89 files, no offenses.

## Notes

The previous status checklist used different milestone names/numbers; it is now
aligned with the authoritative implementation plan. The preview is generated in
memory and does not persist workouts, render the calendar, mutate schedules or
make external HTTP calls; those remain deferred to their documented milestones.
