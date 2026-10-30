# CycleFar — Intervals.icu Integration

## V1 objective

When the rider asks, sync every upcoming structured workout in their active plan to their Intervals.icu calendar.

Export and full reconciliation are manual. The only automatic call is an FTP change refreshing workouts already exported (see [FTP-triggered refresh](#ftp-triggered-refresh)). V1 has no background sync, activity import, completion detection, OAuth or webhooks.

**Source check:** the [official upload guide](https://forum.intervals.icu/t/uploading-planned-workouts-to-intervals-icu/63624) and [public OpenAPI schema](https://intervals.icu/api/v1/docs) were last checked on 2026-10-11 (athlete `0`, bulk upsert/delete) and 2026-10-02 (event fields). Neither documents a count limit for bulk upload, so the full eligible set goes in one request. This is not a live, authenticated certification; specs stub HTTP.

## Authentication

Use the rider's personal API key from Intervals.icu Settings with HTTP Basic auth: username `API_KEY`, password the key. Athlete id `0` means the authenticated athlete; keep that assumption inside the client so OAuth can be added later. Sync only ever uses the signed-in rider's profile and key.

Base API: `https://intervals.icu/api/v1` ([interactive reference](https://intervals.icu/api-docs.html)).

Never expose the API key in logs, rendered HTML, exception messages or source control.

## Calendar API

- **Upsert:** `POST /api/v1/athlete/0/events/bulk?upsert=true`, keyed by CycleFar's `external_id` so repeats don't duplicate events.
- **Delete:** `PUT /api/v1/athlete/0/events/bulk-delete` with `[{"external_id":"cyclefar-workout-123"}]`. Missing events are ignored. The adapter ignores the remote delete count and reports the number of stale local records removed.

The client never lists or searches remote events, and never updates or deletes an event without a CycleFar sync record.

## External ID

Reuse the sync record's external ID, or derive `cyclefar-workout-<planned_workout.id>`. Never use the date: workouts move. The `cyclefar-` prefix avoids collisions with other clients.

## Eligibility

Select, in `scheduled_on` order, every workout where:

- the plan is the signed-in rider's active plan (rechecked under the owner lock);
- status is planned and detail_status is structured;
- `scheduled_on >= Date.current`;
- kind is an executable workout or opener;
- the date is not the target event or time off.

There is no count or horizon cap: persisted structures beyond day 13 are included, but sync never generates outlines or rewrites structures. Report the actual count, including zero.

## Event fields

```json
{
  "category": "WORKOUT",
  "type": "Ride",
  "indoor": true,
  "start_date_local": "YYYY-MM-DDT00:00:00",
  "name": "Threshold 3x12",
  "description": "<Intervals.icu structured workout text>",
  "external_id": "cyclefar-workout-123",
  "moving_time": 3600,
  "icu_ftp": 260,
  "icu_training_load": 72,
  "icu_intensity": 0.85,
  "joules": 650000
}
```

The structured `description` is what matters; the metrics are convenience metadata. Units sent: `moving_time` in seconds, `icu_ftp` in watts, `icu_training_load` as rounded TSS, `icu_intensity` as fractional IF, `joules` as kJ × 1,000. The schema accepts these types but doesn't document units, so live interpretation (especially fractional IF) is unverified. Keep any conversion in the adapter.

**Open discrepancy:** the schema marks `upsertOnUid` and `updatePlanApplied` as required query flags, but the upload guide uses only `upsert=true`. The client follows the guide; check against the live API before changing or certifying the adapter.

## Structured workout text

Intervals.icu accepts text steps with durations (`30s`, `10m`, `1h`), FTP percentages and ranges (`75%`, `95-105%`), ramps, repeat blocks and cue text:

```text
- Warm-up 8m ramp 50-68%

3x
- Threshold 12m 95-100%
- Recovery 5m 50-60%

- Cool-down 7m ramp 55-40%
```

`IntervalsIcu::WorkoutSerializer` writes one line per canonical step, without repeat compression (the block above only illustrates the notation). Steady steps export their FTP range; ramps export the rounded midpoint of each endpoint as `ramp start-end%`. No cadence targets.

Targets stay as percentages of FTP, matching the canonical model; `icu_ftp` gives Intervals.icu the context. Downstream device behaviour is not certified.

## FTP-triggered refresh

FTP changes from Settings and history edits/deletions go through `Settings::FtpMutation`. Only a change in the resulting current FTP triggers `RefreshSyncedWorkouts`, after the local change commits.

- **Scope:** eligible workouts already confirmed as exported (`intervals_event_id` and `last_synced_at` set), including today, openers and distant structures. Never-exported, uncertain and detached identities are skipped.
- **Action:** bulk-upsert those external IDs with current FTP and metrics. No outlines are generated, no stale events deleted, and the athlete's global FTP is untouched.
- No active plan or nothing to refresh means no request and no credentials needed.
- If refresh fails, the FTP change still stands and the rider is told to use Sync.

## Sync reconciliation

1. Resolve the active plan's eligible set.
2. Save the owned sync identities (no event ID, digest or timestamp yet for new ones) before any HTTP.
3. Bulk-upsert the set. Check the response covers every external ID, then save the returned event IDs, digests and timestamps. An incomplete or invalid response keeps the identities for retry and stops before cleanup.
4. Find every sync record the rider owns outside the set, including missed, completed, moved-to-past, deleted and previous-plan workouts.
5. Bulk-delete those external IDs, then delete the local records once deletion is confirmed.

After a successful sync, CycleFar's remote events exactly match the eligible set. A moved workout keeps its external ID and is updated in place. Digests are informational: every sync re-upserts the whole set.

Deleted workouts leave detached sync records (nullable workout key, required `user_id`) so only their owner can clean them up. The service rejects a profile or sync record that belongs to another rider. Completed local workouts, steps, snapshots and feedback never change. With no eligible workouts, the upload is skipped but cleanup still runs. See the [sync sequence diagram](diagrams/sequence-cyclefar-intervals-icu-sync.puml).

Both upload paths (sync and FTP refresh) re-read ownership and eligibility under the plan lock before saving confirmed metadata. If a workout was removed or changed during the HTTP call, the rider gets retry guidance instead of a false confirmation.

## Plan deletion and archival

`Planning::PlanRemover` calls `IntervalsIcu::RemovePlanEvents` first. It deletes the remote events linked to the plan (including completed and missed workouts) and the rider's detached identities, uploads nothing, and leaves other plans' events alone. Plans with no sync identities need no API key.

If credentials are missing or the remote call fails, the plan stays active with its identities kept, and the rider gets Settings/retry guidance. Remote cleanup and local removal commit together; if local removal fails afterwards, deleting the same external IDs again is safe.

Sync, FTP refresh and plan removal share an owner-scoped PostgreSQL session advisory lock, so an in-flight sync can't recreate events after cleanup. Unlike a transaction lock, it lets sync commit identities before HTTP. No database row lock or transaction is held across HTTP.

## Failure handling

- Show a clear partial-sync error; never corrupt local workouts.
- Never mark an event synced until the API confirms it; previously confirmed metadata survives a failed upsert.
- An uncertain upsert keeps its identity, so it can be retried or cleaned up if the workout changes.
- If upload succeeds but cleanup fails, the upload is still recorded and the stale identities are kept for the next sync.
- Missing credentials or rejected requests keep the local change; manual Sync is the recovery path.

## Timeouts and retries

Five-second connect and read timeouts. Retry once on network errors, timeouts and 5xx responses; no endless retries. `external_id` upsert makes retries idempotent.

## Testing

Never call the real API in specs; stub HTTP. Cover:

- serializer output for every step shape;
- the API-key auth header;
- full-calendar selection and stable external IDs;
- upsert mapping, and deleting only CycleFar-owned events;
- 401/403, other 4xx, timeouts and 5xx;
- repeat sync not duplicating events, and a moved workout updating the same event.
