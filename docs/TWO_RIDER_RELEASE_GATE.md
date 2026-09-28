# CYF-74 two-rider release gate

## Automated isolation matrix

The request matrix uses two signed-in accounts and the same browser session. Service and model checks cover the boundaries that do not have a direct route. All Intervals.icu HTTP calls are stubbed.

| Flow | Coverage |
|---|---|
| Public registration, controlled account setup, sign-out, password reset | `spec/requests/registration_spec.rb`, `spec/requests/account_access_spec.rb`, `spec/services/accounts/provision_spec.rb`, `spec/tasks/accounts_spec.rb` |
| First Settings save, concurrent profiles, per-rider FTP/history | `spec/services/settings/update_spec.rb`, `spec/models/user_owned_training_spec.rb`, `spec/services/planning/ftp_recalculator_spec.rb`, `spec/requests/two_rider_release_gate_spec.rb` |
| Preview/edit/confirm, same-browser account switch, plan creation/archive | `spec/requests/training_plan_preview_spec.rb`, `spec/requests/owner_scoped_training_spec.rb`, `spec/requests/two_rider_release_gate_spec.rb` |
| Calendar, workout detail/actions, guessed IDs | `spec/requests/owner_scoped_training_spec.rb`, `spec/requests/two_rider_release_gate_spec.rb` |
| Completion feedback, proposal, missed resolution | `spec/requests/owner_scoped_training_spec.rb`, `spec/requests/two_rider_release_gate_spec.rb` |
| Availability, time off, FTP change, completed and archived history | `spec/requests/owner_scoped_training_spec.rb`, `spec/requests/two_rider_release_gate_spec.rb`, `spec/services/planning/ftp_recalculator_spec.rb` |
| Next-two sync, distinct keys, linked/detached cleanup, retry and remote isolation | `spec/requests/two_rider_release_gate_spec.rb`, `spec/services/intervals_icu/sync_next_two_spec.rb` |
| Cross-owner service inputs and database constraints | `spec/services/intervals_icu/sync_next_two_spec.rb`, `spec/services/planning/time_off_planner_spec.rb`, `spec/models/core_persistence_spec.rb`, `spec/models/user_owned_training_spec.rb`, `spec/lib/legacy_ownership/backfill_spec.rb` |

The integrated request spec checks that one rider's completion, adaptation, missed resolution, availability, time off, FTP update and archive leave the other rider's records and credentials unchanged. It then switches accounts in the same browser and checks private detail and archived history. A second example sends manual sync requests as each rider and checks credentials, upserts and detached cleanup stay with the owner. The separate route matrix checks foreign workout, proposal and time-off IDs against missing IDs; the preview specs check stale drafts after account switching.

## Migration and deployment evidence

On 2026-09-28, `legacy_ownership:preflight` passed in both local development and test databases. Both contained zero users, sessions, profiles, FTP readings, plans, completed workouts and linked/detached sync rows, and both had no pending migrations. The [legacy migration runbook](LEGACY_OWNER_MIGRATION.md) records populated isolated-copy rehearsals for CYF-67, CYF-68 and CYF-72, including failure without an explicit owner, preservation checks and recovery steps. These local checks do not inspect the target deployment database.

Before enabling another rider in a deployment:

1. Complete the still-open Milestone 11 acceptance gate.
2. Inventory the target database, choose and record its existing legacy owner, and rehearse the migration on a restorable copy of that target's data as described in the runbook. Check counts, ownership, completed snapshots, FTP history, encrypted profile data and linked/detached external IDs after migration.
3. Verify configured SMTP delivery and password setup/reset links with the deployed host and queue worker.
4. Re-run the suite and migration checks against the release revision; only then deploy public registration, enable controlled provisioning and mark Milestone 12 complete in `STATUS.md`.

No production-data copy or live SMTP provider was available for this local gate. Operator provisioning remains disabled, and the public registration route should not be deployed with additional riders until the deployment gate passes.
