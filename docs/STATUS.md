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
- [ ] Milestone 12 — Independent riders (planned after Milestone 11; not current)

## Current work

The original milestone slices were delivered, but the repository does not yet satisfy every documented acceptance criterion. Earlier completion entries below are historical reports, not a current certification of full V1 acceptance.

2026-09-24: Reviewed all supporting documents and architecture diagram sources against the current application at `a3a2310`. Updated implemented features, service names, routes, persistence details, missed-workout behaviour, endurance-profile determinism and infrastructure scope. Retained the original bootstrap prompt as historical context.

The [implementation review](REVIEW.md) records open gaps, including material-change replanning, adaptation before/after summaries, unused accepted progression bias, proposal bounds/expiry, move/time-off handling, completion paths, load-cap enforcement and sync cleanup. Current work remains milestone 11; no new milestone or product scope was introduced.

Validation: 1,213 RSpec examples passed; Zeitwerk passed; RuboCop passed (139 files); Brakeman reported no warnings/errors; Bundler Audit and importmap audit reported no vulnerabilities. No live API, browser or deployment acceptance claim is made.

2026-09-25: CYF-1 (PLN-013) restores the last valid plan preview configuration when returning to edit. Added request coverage for custom and event fields, weekly availability, repeated edit visits, invalid correction, revised confirmation and draft consumption. Validation: 1,217 RSpec examples passed; Zeitwerk and RuboCop passed; Brakeman, Bundler Audit and importmap audit clear. Milestone 11 remains open for other acceptance gaps.

2026-09-26: CYF-2 (WKO-005) adds an optional, persisted near-term replan after a material Change Workout action. The changed workout remains a fixed override; accepting regenerates only the bounded following 14-day block using effective availability templates, while dismissal leaves the rest of the plan unchanged. Validation: 1,225 RSpec examples passed; Zeitwerk and RuboCop passed; Brakeman, Bundler Audit and importmap audit clear. Milestone 11 remains open for other acceptance gaps.

2026-09-25: Reviewed all six C4 diagrams against controllers, services and persistence boundaries. Added the preview session draft, home-request materialisation, presentation boundary and replanning dependencies; clarified up-to-two sync selection, cleanup gaps and proposal limitations. Added a diagram guide. Documentation-only validation: document markers, relationship references, relative Markdown links and `git diff --check` passed. PlantUML is not installed, so visual rendering was not performed. Milestone 11 remains open.

2026-09-27: The Rails authentication generator was added after the original V1 milestones. `User`/`Session` models and migrations, a default controller authentication concern, sign-in/sign-out, and password-reset routes/views/mailer are present. No registration or per-user training ownership was added; Settings and plans still use singleton/global data. The SQL schema dump is not yet regenerated for the new tables, existing request specs have not been adapted to authenticated requests, the layout lacks sign-out navigation, and password-reset delivery remains unverified. Supporting documentation and C4 diagrams were updated to describe this state. Documentation validation: Markdown links, six diagram source/relationship checks, `git diff --check`, and Zeitwerk passed. PlantUML is not installed, so visual rendering was not performed. Milestone 11 remains open; this entry does not claim authentication acceptance.

2026-09-27: Applied the generated authentication migrations to the test database and regenerated `db/structure.sql`. Existing training request specs now sign in through the session route; focused model/request specs cover password authentication, redirects, sign-out and password-reset session invalidation. The earlier schema-dump and request-spec gaps above are resolved. Validation: 1,231 RSpec examples passed with no pending examples, Zeitwerk passed, RuboCop passed (156 files), and `git diff --check` passed. The local development database has empty but incompatible pre-existing `users`/`sessions` tables from an untracked migration, so its auth migrations remain pending; no existing development data was changed. Milestone 11 remains open.

2026-09-27: CYF-66 documented the planned independent-rider scope and explicit-owner migration contract in the product, requirements, data model, architecture, UX and implementation plan. `USR-001` through `USR-008` define automated coverage targets for controlled accounts, per-user ownership, two-user isolation, same-browser previews, Intervals.icu sync and cutover. Validation: 1,231 RSpec examples passed, Zeitwerk passed, RuboCop passed (156 files), Brakeman reported no warnings, Bundler Audit and importmap audit found no vulnerabilities, documentation links resolved, and `git diff --check` passed. This is documentation only: no user-owned training schema or multi-rider support has been delivered. Milestone 11 remains current; Milestone 12 is planned and cannot begin its release gate until Milestone 11 is complete.

2026-09-27: CYF-67 added a read-only legacy ownership preflight and a transactional, explicit-owner backfill migration that prepares nullable owner columns for profiles, plans and linked/detached Intervals.icu sync records. The local development/test databases were empty; their previously reported authentication-table conflict is resolved, with matching schema and recorded generator migrations. A populated copy rehearsal rejected a missing owner without partial schema changes, then assigned the selected existing user while preserving checksums of completed history, FTP data, encrypted profile data and sync metadata. See [the migration runbook](LEGACY_OWNER_MIGRATION.md) for cutover and recovery; production databases remain uninspected. Validation: 1,237 RSpec examples, Zeitwerk and RuboCop passed; Brakeman, Bundler Audit and importmap audit were clear. CYF-68 will enforce owner constraints, and Milestone 11 remains current.

2026-09-27: CYF-68 made `RiderProfile` and `TrainingPlan` user-owned, removed the profile singleton and global active-plan constraints, and added database-enforced one-profile/one-active-plan-per-user uniqueness. Existing settings, planning and calendar paths now attach and query those records through the signed-in user; full foreign-record, preview and Intervals.icu isolation remains for later tickets. A populated CYF-67-schema copy rehearsal rejected a missing owner without partial changes, then assigned the explicit owner and preserved completed history, FTP data, encrypted profile and sync metadata. Production remains uninspected and needs its own preflight and copy rehearsal. Validation: 1,241 RSpec examples, Zeitwerk and RuboCop passed; Brakeman, Bundler Audit and importmap audit were clear. Milestone 11 remains current and the Milestone 12 release gate is not complete.

2026-09-27: CYF-69 scoped every training controller record lookup to the authenticated rider's plans. Foreign workout, adaptation-proposal and time-off IDs now receive the same empty 404 as missing IDs; two-user request coverage exercises every training read and mutation route, including archived history, plan archival, FTP Settings, schedule changes and sync entry. Preview draft isolation, domain service ownership and sync metadata isolation remain for CYF-70/71/72. Validation: 1,259 RSpec examples, Zeitwerk and RuboCop passed; Brakeman, Bundler Audit and importmap audit were clear. Milestone 11 remains current and the Milestone 12 release gate is not complete.

2026-09-27: CYF-70 centralized future-workout FTP selection on the owning `TrainingPlan` and passed the saved profile directly to FTP recalculation, binding watt input to that profile's user. Two-owner service coverage now checks planning, horizon materialization, manual add/edit/copy, completion, presentation, unchanged second-rider credentials/history, and concurrent first Settings saves under per-user row locks. Completed structures and watt snapshots remain unchanged after FTP updates. Validation: 1,263 RSpec examples, Zeitwerk and RuboCop passed; Brakeman, Bundler Audit and importmap audit were clear. Milestone 11 remains current; preview and sync isolation still block the Milestone 12 release gate.

2026-09-27: CYF-71 binds each session-backed plan preview draft to its authenticated creator. Opening the edit form or confirming a draft under another account clears it, including legacy drafts with no owner; the second rider can create a fresh preview and plan. Same-rider preview, Back to edit and confirmation remain intact. Request specs cover same-browser account switching, stale confirmation rejection and a fresh second-rider confirmation. Validation: 1,266 RSpec examples, Zeitwerk and RuboCop passed; Brakeman, Bundler Audit and importmap audit were clear. Milestone 11 remains current; sync isolation still blocks the Milestone 12 release gate.

2026-09-27: CYF-72 requires an owning user on every Intervals.icu sync record, including detached records. Reconciliation now queries only that rider's metadata and rejects a profile or linked sync belonging to another owner. The migration derives missing linked owners from plans, requires an explicit existing owner for unassigned detached rows, and enforces `NOT NULL` plus a user foreign key. An isolated populated-copy rehearsal confirmed rollback without an owner and preservation of external IDs/payload digests with one. Two-rider specs cover separate HTTP credentials, next-two selection, stale linked/detached cleanup, repeat sync and failed-cleanup retry. Validation: 1,272 RSpec examples, Zeitwerk and RuboCop passed; Brakeman, Bundler Audit and importmap audit were clear. Milestone 11 remains current; controlled account provisioning and the full two-user release gate remain.

2026-09-28: CYF-73 adds a gated operator task that creates an independent rider account with a random password and immediately mails a short-lived setup link; a failed delivery rolls the account back. The layout shows account identity and sign-out, which destroys the database session and clears Rails session drafts. Password reset keeps the same response for known/unknown addresses and accepts normalized email input. Production now requires an SMTP sender, credentials and HTTPS link host from environment variables; configuration boot was verified with local dummy endpoints, while live provider delivery remains unverified. Request, service and task specs cover provisioning, private sign-in, sign-out, mail delivery through the test adapter, reset and old-session invalidation. Validation: 1,279 RSpec examples, Zeitwerk and RuboCop passed; Brakeman, Bundler Audit and importmap audit were clear. Milestone 11 remains current; CYF-74's full two-user release gate remains before enabling additional riders.

2026-09-28: CYF-74 added an integrated two-rider request matrix spanning feedback/adaptation, missed resolution, availability/time off, FTP updates, completed and archived history, same-browser account switching and manual Intervals.icu sync with distinct credentials and detached records. Existing route, service, model and migration specs cover foreign IDs, preview drafts, concurrent first saves and owner constraints; see the [release-gate matrix](TWO_RIDER_RELEASE_GATE.md). Local development and test ownership preflights passed with zero training data and no pending migrations; prior populated-copy migration rehearsals are recorded in the [migration runbook](LEGACY_OWNER_MIGRATION.md). Validation: 1,281 RSpec examples passed, Zeitwerk and RuboCop passed (170 files), Brakeman found no warnings, and Bundler Audit and importmap audit found no vulnerabilities. The target database copy and live SMTP delivery have not been verified. Milestone 11 remains current, Milestone 12 remains planned, and additional rider provisioning remains disabled.

2026-09-28: Refreshed the root and supporting guides, implementation review and all six architecture diagram sources against the CYF-1/2 and CYF-66–74 code and release-gate evidence. Removed stale singleton, missing schema, absent sign-out/mail and missing material-change replan claims. Documented the implemented owner boundaries and automated two-rider matrix separately from the open target-data rehearsal, live SMTP check and Milestone 11 acceptance work. Documentation validation: local Markdown links, diagram relationship references and document markers, and `git diff --check` passed. PlantUML is unavailable locally, so visual rendering remains unverified. No application code changed; Milestone 11 remains current.

2026-09-28: Added a public homepage with Sign In and Register choices, a self-registration form that creates a private rider account and signs them in, and registration links in the public navigation and sign-in form. Private training pages still require authentication. Request specs cover the entry paths, registration success and validation, and signed-in registration rejection. Validation: 1,285 RSpec examples passed; Zeitwerk and RuboCop passed (172 files); Brakeman and importmap audit found no warnings or vulnerabilities; Bundler Audit found none using its installed advisory database (updating that database was blocked by local filesystem permissions). This user-requested change adds local public registration; the target-data rehearsal, live mail check and Milestone 11 acceptance gate remain open before deployment with additional riders. Milestone 11 remains current.

2026-09-28: CYF-75 makes a valid plan-preview submission redirect to a session-backed GET preview, so refreshing the preview works without resubmitting the form or persisting a plan. Missing or foreign-account drafts return to the plan form; invalid submissions still show validation errors. Request specs cover refresh, draft ownership and the updated redirect flow. Validation: 1,287 RSpec examples passed; Zeitwerk and RuboCop passed (172 files); Brakeman reported no warnings; Bundler Audit and importmap audit found no vulnerabilities. Milestone 11 remains current for the other acceptance gaps.

2026-09-29: CYF-16 makes the no-plan calendar exactly four complete Monday–Sunday weeks, beginning with the previous week, regardless of month length. PLN-001 and the UX/architecture descriptions now match; request coverage checks both longer and shorter month-boundary cases. Validation: 1,288 RSpec examples passed; Zeitwerk and RuboCop passed (172 files); Brakeman reported no warnings; Bundler Audit and importmap audit found no vulnerabilities. Milestone 11 remains current for the other acceptance gaps.

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
