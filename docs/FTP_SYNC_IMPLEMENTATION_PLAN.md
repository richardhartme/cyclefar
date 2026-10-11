# Refresh previously synced workouts after an FTP change

Jira: [CYF-83](https://richardhartme.atlassian.net/browse/CYF-83).

## Problem and reproduction

Adding or changing the rider's current FTP updates future workout watts and metrics in CycleFar, but previously exported Intervals.icu events retain their old FTP context until the rider manually syncs again.

1. Create an active plan and manually sync upcoming structured workouts to Intervals.icu.
2. Change FTP in Settings, or edit/delete an FTP-history reading so the effective current FTP changes.
3. CycleFar displays new targets; Intervals.icu has received no replacement event payload.

Expected: automatically refresh already-synced, eligible upcoming workouts after the current FTP changes. The user explicitly confirmed this scope on 11 October 2026. Initial export and full-calendar reconciliation remain manual.

Impact: the two calendars can disagree about planned power targets and work. Source inspection confirms the missing remote call; no authenticated production reproduction was performed.

## Findings

- `Settings::Update` creates readings; `Settings::FtpHistory#refresh_current!` determines current FTP by newest effective date/highest-ID tie-break and invokes `Planning::FtpRecalculator` only when current watts change.
- The recalculator updates future structured metrics, preserving canonical percentage steps and completed snapshots. Neither settings/history path calls Intervals.icu.
- `IntervalsIcu::WorkoutSerializer` already sends percentage-based descriptions, `icu_ftp`, and derived metrics.
- `IntervalsIcu::SyncCalendar` re-exports current FTP on the next manual sync, but also uploads never-exported workouts and deletes stale events. Calling it wholesale during an FTP save would exceed the requested scope.
- Existing sync rows contain stable external IDs, confirmed event IDs, payload digests and successful-sync timestamps. Rows retained before uncertain uploads are not proof of a successful prior sync.
- Sync and Delete/Archive share `IntervalsIcu::Synchronization.with_owner_lock`.

## Implementation plan

1. **Document the behavior contract.** Extend SET-001/ICU-001 and owner-isolation coverage in `docs/REQUIREMENTS.md`. Clarify the narrowly triggered, foreground refresh after an explicit current-FTP mutation. Retain the V1 prohibition on automatic background sync. Align `docs/INTERVALS_ICU.md`, `docs/ARCHITECTURE.md`, `docs/PRODUCT.md` and `docs/UX.md`; this is a deliberate extension of the current manual-only behavior, not an existing requirement.

2. **Share eligible selection and confirmed upload handling.** Extract reusable parts of `SyncCalendar` where useful, and introduce an explicit service such as `IntervalsIcu::RefreshSyncedWorkouts`. Select only the owning rider's active-plan workouts that satisfy existing manual-sync eligibility AND have confirmed prior sync metadata (event ID and successful-sync timestamp). Include today and every already structured future workout, including openers and structures beyond day 13. Exclude past/completed/missed/outline workouts, event/time-off dates, archived plans, detached identities, unsynced workouts and uncertain-only uploads. Do not generate structures or perform stale-event deletion.

3. **Trigger from every current-FTP mutation.** Add a shared explicit settings orchestration boundary for Settings saves/new readings, history edits, date reordering and deletion fallback. Compare current FTP before and after the transactional history/profile/metric update. Only a committed change in current watts triggers refresh; old-history edits, same-watt saves and failed validation do not. Keep `Planning::FtpRecalculator` local and free of HTTP. Use explicit services rather than hidden model callbacks.

4. **Preserve transaction and concurrency boundaries.** Acquire the existing owner advisory lock before the local user/plan locks, using consistent ordering for all FTP mutation entry points. Commit FTP/history/future-metric updates and release row locks before remote HTTP, while retaining the owner advisory lock through the refresh. Recheck active plan and reload the profile/current FTP under that lock before building payloads; also reload the profile inside queued manual sync so it cannot send a stale FTP object. Serialize against manual sync, another FTP mutation and Delete/Archive. Audit workout status changes during upload and ensure confirmed metadata never becomes attached to a deleted/replaced or foreign workout. No network call belongs inside the FTP database transaction.

5. **Refresh remote payloads safely.** Use the existing client and serializer to bulk-upsert the selected events under their saved external IDs. Send the latest `icu_ftp`, recalculated work/power metrics and unchanged canonical percentage descriptions. Validate the complete confirmation by external ID before updating event IDs, payload digests or successful-sync timestamps. Preserve the existing confirmed metadata on timeout, API rejection or incomplete responses, and retain idempotent recovery through manual Sync. Do not update the athlete's global FTP, import activities or touch unrelated events. No schema migration is expected.

6. **Return truthful save/refresh results.** Keep the local FTP save successful even if remote refresh fails or credentials are unavailable. Controllers should report, for example, “FTP saved. Refreshed 4 workouts in Intervals.icu.” or “FTP saved, but Intervals.icu workouts could not be refreshed. Check your API key and use Sync to retry.” Avoid an FTP validation error or a false remote-success message after a committed save. Skip HTTP when there are no confirmed eligible exports; an unconnected rider can save FTP normally. Reuse existing bounded timeouts and transient retry. Never expose API keys in output or logs.

7. **Add regression coverage and run gates.** Extend settings/update/history services, FTP/settings request specs, serializer/client specs, sync/refresh service specs and owner-lock concurrency coverage. Use WebMock or injected clients only. Verify actual commit-before-HTTP behavior with non-transactional test coverage where required. Run focused specs, then `bundle exec rspec`, `bin/rails zeitwerk:check`, `bin/rubocop`, `bin/brakeman --no-pager`, `bin/bundler-audit` and `bin/importmap audit`.

## Acceptance criteria

- Adding a new current reading, editing the current reading, changing date ordering or deleting the newest reading automatically refreshes eligible previously synced events when resulting current watts change.
- Changing 260 W to 300 W sends `icu_ftp: 300` and recalculated derived metrics using the same external IDs; a 60–70% step stays 60–70%, with derived targets of 180–210 W. Workout dates, duration and canonical structure remain unchanged.
- Today, openers, more than two exports and persisted structures beyond day 13 are covered. Never-synced workouts and outlines are not exported/materialized.
- Editing an older reading without changing current FTP, saving identical watts, changing only credentials or failing validation performs no FTP-triggered refresh.
- Completed workout structure, historical FTP/watts, metrics and feedback remain unchanged; past/missed/completed/archived/event/time-off records and remote activities are untouched.
- Missing/rejected keys, timeout/5xx and incomplete/out-of-order/duplicate confirmations have explicit coverage. A remote failure preserves the committed FTP and prior confirmed sync metadata; manual Sync retries using stable identities without duplicates.
- Zero eligible confirmed exports produces no HTTP. No active plan or no connection does not block a valid FTP save.
- Two riders use only their own credentials, plans, FTP readings and sync identities; unrelated remote events remain untouched.
- Concurrent FTP updates/manual sync use the latest committed FTP; concurrent Delete/Archive cannot recreate removed-plan events. Test the shared lock ordering without deadlock.
- Initial export/full-calendar cleanup remains manual; this change adds no background job, polling, new sync-count setting or automatic athlete-FTP update.

## Related work and API verification

- [CYF-78](https://richardhartme.atlassian.net/browse/CYF-78): FTP history and current-reading selection.
- [CYF-82](https://richardhartme.atlassian.net/browse/CYF-82): full eligible manual export; currently promises FTP updates on the next manual sync.
- [CYF-79](https://richardhartme.atlassian.net/browse/CYF-79): plan-removal cleanup and shared owner locking.
- [CYF-14](https://richardhartme.atlassian.net/browse/CYF-14) / [CYF-72](https://richardhartme.atlassian.net/browse/CYF-72): reconciliation and rider isolation.

The [official upload guide](https://forum.intervals.icu/t/uploading-planned-workouts-to-intervals-icu/63624), checked 11 October 2026, documents bulk upsert with stable external IDs. Recheck the [public API schema](https://intervals.icu/api/v1/docs) during implementation and verify that updating `icu_ftp` changes the displayed/downloaded workout power basis for percentage descriptions. That live interpretation remains an implementation validation requirement; adapt the integration boundary if needed without replacing canonical percentage steps with absolute watts.
