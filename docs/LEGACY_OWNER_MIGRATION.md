# CYF-67 legacy owner preparation

CYF-67 added nullable `user_id` columns to `rider_profiles`, `training_plans` and `intervals_icu_syncs`, assigning existing rows only to an explicitly selected existing `User`. CYF-68 now enforces required profile and plan ownership with foreign keys and per-user uniqueness. Sync ownership and full request isolation remain later work, so multiple accounts must remain disabled until the isolation gate passes.

## Inventory each target database

Run this separately against every target database using its normal Rails database configuration. It reads counts for users, sessions, profiles, FTP readings, plans, completed workouts, and linked and detached sync records. It never reads or prints the Intervals.icu API key.

```bash
bin/rails legacy_ownership:preflight
```

If training data exists, select the **existing** account that owns it. Inspect its identity through the normal account administration process and record the choice in the cutover record. Do not choose the first user or use a current session as an implicit owner. Re-run the preflight with its numeric ID:

```bash
CYCLEFAR_LEGACY_OWNER_USER_ID=<existing-user-id> bin/rails legacy_ownership:preflight
```

The preflight fails if the owner is missing or invalid, if the generated authentication schema is incomplete, if multiple legacy profiles exist, if an FTP reading or workout is orphaned, if a linked sync has no workout/plan, if a sync ID is outside the `cyclefar-` namespace, or if any already assigned owner differs. Detached sync rows still require the explicit owner. A failed preflight changes no records.

Before migration, verify that the generated `users` and `sessions` migrations are recorded and their tables have the expected columns. A database with pre-existing incompatible authentication tables must be repaired **on a copy first**: preserve its rows, compare its columns, indexes and constraints with the generated migrations, then apply a reviewed data-preserving repair and record the migration versions. Do not drop rider tables or mark migrations applied without matching schema. The local development database's previously reported conflict has since been resolved; both generated auth migrations are recorded, the tables have the expected columns, and all local training counts were zero on 2026-09-27.

## Rehearsal and cutover

1. Take a restorable PostgreSQL backup or copy of the target database. Keep the source available and stop application writes for the final cutover. Never test destructive steps on the only copy.
2. Run the preflight on the copy with the selected existing owner. Record the counts and owner ID, without exporting the API key.
3. Record checksums or a database dump for the profile (including encrypted key), FTP readings, plans, completed workouts, workout steps/feedback, and sync rows. Exclude only the three new `user_id` fields from before/after comparisons.
4. Run `CYCLEFAR_LEGACY_OWNER_USER_ID=<existing-user-id> bin/rails db:migrate` on the copy. Verify every profile, plan and sync row has that owner, including detached sync rows; verify the old-row checksums and external IDs are identical.
5. Repeat the preflight and migration on the target only after the copy passes. The CYF-68 migration reruns the explicit-owner backfill in the same transaction before adding required constraints. Recheck row counts, ownership and preservation after migration. Keep the backup until the later two-user isolation gate passes.

Both migrations run in PostgreSQL transactions. An absent or inconsistent owner stops before assigning legacy rows or enforcing required ownership. Re-running the backfill with the same owner is idempotent. If the production cutover fails, stop writes, inspect the transaction/migration state and preflight output, correct the cause on a new copy, then retry. If the database is inconsistent or the source data changed unexpectedly, restore the pre-cutover backup and investigate before attempting another migration. The migrations are intentionally irreversible because removing ownership would discard the selected account.

## Local rehearsal evidence (2026-09-27)

The local development and test databases both had zero users, sessions, profiles, FTP readings, plans, completed workouts and sync rows. Their generated auth migrations and schema were present. The nullable-column migration applied to the empty development database; the read-only preflight passed for development and test.

A separate copy of the test database was populated with two users, one profile, one FTP reading, active and archived plans, a completed workout with steps and feedback, and linked and detached sync rows. Without an owner, the migration failed and left no new columns or migration marker. With the explicitly selected existing user, all one profile, two plans and two sync rows were assigned to that user. Checksums of the profile, FTP reading, both plans, completed workout, steps, feedback and sync metadata (excluding only the new owner columns) were identical before and after. No hosted or production database was available for inspection; its preflight and rehearsal remain a deployment prerequisite.

For CYF-68, a separate copy was reset to the CYF-67 schema and populated with the same record types. Its profile and plan owner fields were cleared to simulate legacy rows. Without `CYCLEFAR_LEGACY_OWNER_USER_ID`, the migration failed before changing ownership or constraints. With an explicit existing owner, it assigned the profile and both plans, enforced their non-null columns and indexes, and preserved checksums of the profile, FTP reading, plans, completed workout, steps, feedback and sync metadata. The copy was removed after the rehearsal. Production preflight and a production-data copy rehearsal remain required before deployment.
