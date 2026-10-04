# CycleFar — Intervals.icu Integration

## V1 objective

On explicit rider action, sync the next two upcoming structured cycling workouts from the active plan to the rider's Intervals.icu calendar.

No automatic sync, activity import, completion detection, OAuth or webhook handling in V1.

The request details below describe the implemented adapter and owner-scoped reconciliation. On 2026-10-04, the [official upload guide](https://forum.intervals.icu/t/uploading-planned-workouts-to-intervals-icu/63624) and the [public OpenAPI schema](https://intervals.icu/api/v1/docs) were rechecked for athlete `0` and bulk upsert/delete (CYF-14); event field names/types were checked on 2026-10-02. This is not a live authenticated sync certification. Local specs stub HTTP.

## Authentication

Use the rider's personal API key from Intervals.icu Settings. The client uses HTTP Basic auth with username `API_KEY` and the key as password.

Intervals.icu documents API-key authentication and allows athlete id `0` to mean the authenticated athlete. Keep athlete-id assumptions isolated in the client so OAuth can be added later. Manual sync uses only the signed-in rider's profile and API key. The [interactive API reference](https://intervals.icu/api-docs.html) loads the public schema linked above.

Base API:

```text
https://intervals.icu/api/v1
```

Never expose the API key in logs, rendered HTML, exception messages or source control.

## Implemented calendar API approach

Use bulk calendar-event upsert with stable `external_id` values owned by CycleFar.

Upsert endpoint:

```text
POST /api/v1/athlete/0/events/bulk?upsert=true
```

The Intervals.icu guide describes `external_id` as a way for external applications to upsert their own calendar events without duplicating them.

The client deletes by external ID using `PUT /api/v1/athlete/0/events/bulk-delete` with a JSON array such as `[{"external_id":"cyclefar-workout-123"}]`. It does not list or search unrelated remote events. The upstream guide says missing events are ignored; the schema returns a `DeleteEventsResponse`, whereas upsert returns an array of `Event` records. The adapter ignores the remote delete count and reports the number of stale local records removed.

Never delete/update calendar events that lack CycleFar's ownership marker/sync record.

## External ID

Use the existing sync record's external ID, or derive it from the durable workout database ID:

```text
cyclefar-workout-<planned_workout.id>
```

Do not use date alone; workouts can move.

If integer DB ids are used locally, prefix them clearly to avoid collisions with other clients.

## Eligibility: “next two workouts”

Select the first two by `scheduled_on` where:

- plan is the signed-in rider's active plan (selected by the controller; the service itself does not validate plan status);
- status = planned;
- detail_status = structured;
- scheduled_on >= Date.current;
- kind is an executable workout/opener;
- exclude target event;
- exclude time off;
- exclude FTP Test because V1 does not define an executable FTP-test protocol.

If fewer than two are available, sync what exists and explain the count.

## Event fields

Send at least:

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

Treat optional metric fields as convenience metadata. The structured description is the key executable representation.

The payload above matches the current serializer's shape. The public schema's `EventEx` accepts these fields: durations/FTP/load/joules are integers and `icu_intensity` is a float. The serializer sends seconds for `moving_time`, watts for `icu_ftp`, rounded TSS for `icu_training_load`, fractional IF for `icu_intensity` and kJ multiplied by 1,000 for `joules`. The schema supplies no unit descriptions for those fields; live interpretation of the optional metrics, particularly fractional IF, remains unverified. Keep any needed conversion at this adapter boundary.

The schema also marks `upsertOnUid` and `updatePlanApplied` query flags required, while the official upload guide demonstrates only `upsert=true`. The current client follows the guide. Verify this discrepancy against the live API when changing or certifying the adapter.

## Structured workout serialization

Intervals.icu supports text-based workout steps with percentage-of-FTP targets and ranges, e.g.:

```text
- Warm-up 8m ramp 50-68%

3x
- Threshold 12m 95-100%
- Recovery 5m 50-60%

- Cool-down 7m ramp 55-40%
```

Supported constructs documented by Intervals.icu include:

- durations such as `30s`, `10m`, `1h`;
- FTP percentages and ranges (`75%`, `95-105%`);
- ramps;
- repeat blocks;
- cue text.

The Rails domain stores expanded canonical steps. `IntervalsIcu::WorkoutSerializer` currently emits one flat text line per step, without repeat compression. Steady steps export FTP ranges; ramps export the rounded midpoint of each endpoint range as `ramp start-end%`. The repeat block above illustrates the notation, not the current serializer output.

Do not send cadence targets because V1 does not prescribe cadence.

## FTP and target ranges

Use percentage-of-FTP targets in the Intervals.icu workout description rather than converting every step to absolute watts. This preserves the intended structure and matches the app's canonical model.

Send `icu_ftp`/current FTP where supported so Intervals.icu has the correct context.

## Sync reconciliation

Current call order:

1. Resolve the active plan's next-two eligible set (or fewer when fewer exist).
2. Build payloads with stable external IDs and transactionally retain their owned sync identities before HTTP. New records have no event ID, digest or successful-sync timestamp yet.
3. Bulk-upsert the set, then transactionally save confirmed returned event IDs, digests and timestamps.
4. Find all stale sync records owned by this rider outside the selected set, including missed/completed, past-moved, deleted and previous-plan workouts.
5. Bulk-delete those stale external IDs, then transactionally destroy their local sync records only after confirmed deletion.

Digests are stored for reference; repeat sync still upserts both selected workouts. Deleted local workouts leave detached sync records via a nullable workout foreign key and required `user_id`, allowing only their owner to clean them up. The service rejects a profile or linked sync record belonging to another rider. The serializer exports stored estimated metrics; current FTP is passed separately and percentage steps remain canonical.

CycleFar's tracked remote calendar-event set matches the next-two set after a successful sync. A moved workout still selected is updated under its original external ID; every tracked event outside the set is removed, even when its former workout is completed or belongs to an archived plan. Only owned calendar events are deleted: there are no activity/history API calls, and completed local workouts, steps, snapshots and feedback remain unchanged (CYF-14).

The [manual sync sequence](diagrams/sequence-cyclefar-intervals-icu-sync.puml) shows the separate local transactions, remote calls and failure paths. With no eligible workouts, upload is skipped and all stale owned events are still reconciled.

## Partial failure

Prefer one bulk request for the two upserts when possible.

If reconciliation requires delete + upsert calls and one part fails:

- show a clear partial-sync error;
- do not corrupt local workouts;
- retain enough sync metadata to retry idempotently;
- never mark an event successfully synced until confirmed.

An uncertain upsert retains its identity for retry or cleanup if the workout changes before retry. Previously confirmed metadata remains unchanged on upsert failure. When upload succeeds but cleanup fails, confirmed upload metadata remains saved, stale identities remain available, and the rider sees a partial-sync message with retry guidance. Repeated cleanup of an already deleted event is safe because the API ignores missing events.

## Timeouts/retries

For manual V1 sync:

- use five-second connect/read timeouts;
- no endless retries;
- retry once for network errors/timeouts and 5xx responses;
- idempotency comes from `external_id` upsert.

## Testing

Do not hit the real Intervals.icu API in specs.

Test:

- serializer output for every supported step shape;
- API-key auth header construction;
- next-two selection;
- stable external IDs;
- upsert mapping;
- deletion only of CycleFar-owned events;
- API 401/403 behaviour;
- 4xx validation errors;
- timeouts/5xx;
- repeat sync does not duplicate events;
- moved workout updates same external event rather than creating another.

Use WebMock or an equivalent HTTP stubbing library if added to the test stack.
