# CycleFar Build Status

Current milestone: 11 — Polish and hardening (acceptance follow-up)
Status: Reopened after the 2026-09-24 documentation review; known V1 acceptance gaps remain

## Milestones

Numbering follows `IMPLEMENTATION_PLAN.md` and `CODEX_TASK_01.md`.

- [x] Milestone 0 — Bootstrap and guardrails
- [x] Milestone 1 — Settings and core persistence
- [x] Milestone 2 — Pure workout engine
- [x] Milestone 3 — Plan preview engine
- [x] Milestone 4 — Persist plan + continuous calendar
- [x] Milestone 5 — Workout detail and manual editing
- [x] Milestone 6 — Completion, overdue and adaptations
- [x] Milestone 7 — Missed workouts and schedule changes
- [x] Milestone 8 — Time off and return to training
- [x] Milestone 9 — FTP lifecycle
- [x] Milestone 10 — Intervals.icu sync
- [ ] Milestone 11 — Polish and hardening (original delivery complete; acceptance follow-up reopened)

## Current work

The original milestone slices were delivered, but the repository does not yet satisfy every documented acceptance criterion. Earlier completion entries below are historical reports, not a current certification of full V1 acceptance.

2026-09-24: Reviewed all supporting documents and architecture diagram sources against the current application at `a3a2310`. Updated implemented features, service names, routes, persistence details, missed-workout behaviour, endurance-profile determinism and infrastructure scope. Retained the original bootstrap prompt as historical context.

The [implementation review](REVIEW.md) records open gaps, including material-change replanning, adaptation before/after summaries, unused accepted progression bias, proposal bounds/expiry, move/time-off handling, completion paths, load-cap enforcement and sync cleanup. Current work remains milestone 11; no new milestone or product scope was introduced.

Validation: 1,213 RSpec examples passed; Zeitwerk passed; RuboCop passed (139 files); Brakeman reported no warnings/errors; Bundler Audit and importmap audit reported no vulnerabilities. No live API, browser or deployment acceptance claim is made.

2026-09-25: CYF-1 (PLN-013) restores the last valid plan preview configuration when returning to edit. Added request coverage for custom and event fields, weekly availability, repeated edit visits, invalid correction, revised confirmation and draft consumption. Validation: 1,217 RSpec examples passed; Zeitwerk and RuboCop passed; Brakeman, Bundler Audit and importmap audit clear. Milestone 11 remains open for other acceptance gaps.

## Later feature changes

After the original milestone delivery, the repository added:

- no-plan calendar, full-width weekly TSS chart and revised graph/card/step styling;
- retained missed-workout cards (MIS-001);
- Copy and Add Workout (WKO-007/008), including manual Opener selection;
- Event time-off reason and optional time-off names;
- time-off replanning that respects later availability changes and one-week overrides;
- the endurance-profile and variation-key changes recorded below.

2026-09-21: Added randomly selected endurance profiles (sustained, alternating low/high, and undulating). Selection is persisted during generation; forecasts remain deterministic and saved workouts remain stable. Added duration, zone, load and materialisation regression coverage. Also corrected fractional return-to-training stage calculation exposed by the full suite. Validation: 1,170 examples passed, Zeitwerk passed, RuboCop passed.

2026-09-21: Renamed endurance profiles to `sustained`, `alternating`, and `undulating` throughout generation, forecasting, editing and tests. Migrated uncompleted workouts; immutable completed records retain historical keys. Validation: 1,212 examples passed, Zeitwerk passed, RuboCop passed.

2026-09-21: Replaced remaining recovery/intensity/opener letter keys with descriptive variation names and migrated uncompleted records. Completed history remains immutable. Validation: 1,212 examples passed, Zeitwerk passed, RuboCop passed.

## Infrastructure

2026-09-24: Added a CloudFormation alternative under `infra/cloudformation/` for the single-server AWS architecture, with generated Secrets Manager database credentials and optional existing/new Route 53 hosted zones. Added safe example parameters and manual change-set/deployment/cleanup instructions. Application deployment remains a separate Kamal step. Validated locally with cfn-lint 1.57.0 for eu-west-2; no AWS validation API calls, change sets, stacks or resources were created.

2026-09-12: Initial AWS Terraform configuration added locally (not applied).

- Added a small single-server VPC, EC2, Elastic IP and private encrypted RDS PostgreSQL design under `infra/`.
- Restricted RDS PostgreSQL access to the application security group and added optional existing-hosted-zone Route 53 support for `cyclefar.com`.
- Added Terraform state, plan and secret-variable ignore rules, plus safe variables and operations documentation for a later manual apply and Kamal configuration.
- `terraform fmt -check` and `terraform validate` were not run because Terraform is not installed in the local workspace.

## Original milestone delivery history

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

2026-09-05: Milestone 4 implemented locally (not committed by Codex).

- Added transactional confirmation from the preview, persisted plan phases, availability, event and high-level prescriptions.
- Materialised canonical steps for the 14-day horizon only and added an idempotent horizon materializer.
- Added the continuous Monday–Sunday calendar with phase/recovery treatment, weekly totals, structured/outlines cards, mini SVG profiles, FTP-test and event cards.
- Added persistence and request specs for preview equivalence, horizon materialisation and calendar rendering.
- `bundle exec rspec`: 1097 examples, 0 failures.
- `bin/rails zeitwerk:check`: passed.
- RuboCop: 94 files, no offenses.

2026-09-05: Milestone 5 implemented locally (not committed by Codex).

- Added Turbo Frame workout detail, canonical step/metric presentation and manual workout controls.
- Added deterministic Same, Easier, Harder, ±15-minute and Change Workout regeneration with material-change messaging.
- Added collision-safe moves and guards against completed-workout changes; no individual step-edit route exists.
- `bundle exec rspec`: 1105 examples, 0 failures.
- `bin/rails zeitwerk:check`: passed.
- RuboCop: 98 files, no offenses.

2026-09-05: Milestone 6 implemented locally (not committed by Codex).

- Added transactional manual completion with feedback and frozen FTP/target/metric snapshots.
- Added awaiting-status and completed calendar states, deterministic adaptation evaluation, and explicit proposal accept/reject actions.
- Added bounded long-term intensity-bias updates only after proposal acceptance.
- `bundle exec rspec`: 1110 examples, 0 failures.
- `bin/rails zeitwerk:check`: passed.
- RuboCop: 104 files, no offenses.

2026-09-05: Milestone 7 implemented locally (not committed by Codex).

- Added explicit missed-workout resolution for leave unchanged, collision-safe move and a deterministic replan of the next 14 days without training-debt stacking.
- Added one-week and ongoing availability changes, immutable availability-template history, future high-level re-prescription and horizon rematerialisation.
- Preserved past/completed workouts, FTP tests, openers, phases and target events during schedule changes; re-prescription runs through the existing plan engine so its load-cap rules remain in effect.
- Added service and request coverage for missed resolution, availability versions, one-workout-per-date protection, calendar actions and completed/past preservation.
- `bundle exec rspec`: 1118 examples, 0 failures.
- `bin/rails zeitwerk:check`: passed.
- RuboCop: 112 files, no offenses.
- Brakeman and Bundler Audit: no warnings or vulnerabilities.

2026-09-05: Milestone 8 implemented locally (not committed by Codex).

- Added add/remove time-off actions with Holiday, Illness, Recovery and Other reasons, including validated user-selected return-ramp days for Illness and Recovery.
- Re-prescribed future training around time off without extending the fixed plan end; planned FTP tests and openers in time-off or re-entry dates are removed while completed workouts, phases and target events remain intact.
- Added deterministic Holiday/Other resumption and four-stage illness/recovery re-entry prescriptions, including collapsed short ramps and horizon materialisation.
- Added calendar time-off cards and request/service coverage for changes, completed-workout protection, event/taper interactions, short and long ramps, removal and fixed plan dates.
- `bundle exec rspec`: 1123 examples, 0 failures.
- `bin/rails zeitwerk:check`: passed.
- RuboCop: 116 files, no offenses.
- Brakeman and Bundler Audit: no warnings or vulnerabilities.

2026-09-05: Milestone 9 implemented locally (not committed by Codex).

- Added an FTP Test detail flow that records an assessment separately and directs the rider to update Settings with the result.
- Added transactional recalculation of future planned structured-workout metrics when FTP changes, while keeping canonical percentage steps and all completed snapshots untouched.
- Materialisation, schedule re-prescription, manual workout edits and workout-detail target-watt displays now use the rider’s current FTP context.
- Added service and request coverage for current future watts, preserved percentage structures and completed snapshots, and FTP-test completion.
- `bundle exec rspec`: 1126 examples, 0 failures.
- `bin/rails zeitwerk:check`: passed.
- RuboCop: 118 files, no offenses.
- Brakeman and Bundler Audit: no warnings or vulnerabilities.

2026-09-06: Milestone 10 implemented locally (not committed by Codex).

- Added explicit manual sync of exactly the next two executable structured workouts to Intervals.icu.
- Added an isolated API-key-authenticated bulk upsert/delete client, stable CycleFar-owned external IDs, canonical workout-builder serialization and safe retry/error handling.
- Reconciled moved and deleted CycleFar workouts while preserving unrelated events, and added calendar sync feedback and last-sync status.
- Added client, serializer, reconciliation and request coverage, including API-key error handling and current FTP context.
- `bundle exec rspec`: 1139 examples, 0 failures.
- `bin/rails zeitwerk:check`: passed.
- RuboCop: 127 files, no offenses.
- Brakeman and Bundler Audit: no warnings or vulnerabilities.

2026-09-06: Milestone 11 implemented locally (not committed by Codex).

- Added an idempotent, development-only 12-week sample plan with the documented 260 W FTP and weekly training template.
- Improved calendar efficiency by eager-loading workout phases with structured steps, and added accessible skip navigation.
- Improved keyboard navigation and enlarged the detailed workout graph.
- Added confirmed destructive actions and archive/delete-plan handling that removes planned workouts while retaining completed history.
- Rechecked empty/error states, plan warnings and encrypted API-key log filtering through the existing request coverage.
- `bundle exec rspec`: 1142 examples, 0 failures.
- `bin/rails zeitwerk:check`: passed.
- RuboCop: 127 files, no offenses.
- Brakeman and Bundler Audit: no warnings or vulnerabilities.

## Notes

The previous status checklist used different milestone names/numbers; it is now
aligned with the authoritative implementation plan.
