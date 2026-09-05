# CycleFar — Intervals.icu Integration

## V1 objective

On explicit rider action, sync the next two upcoming structured cycling workouts from the active plan to the rider's Intervals.icu calendar.

No automatic sync, activity import, completion detection, OAuth or webhook handling in V1.

## Authentication

Use the rider's personal API key from Intervals.icu Settings.

Intervals.icu documents API-key authentication and allows athlete id `0` to mean the authenticated athlete. Keep athlete-id assumptions isolated in the client so OAuth/multi-rider support can be added later.

Base API:

```text
https://intervals.icu/api/v1
```

Never expose the API key in logs, rendered HTML, exception messages or source control.

## Recommended calendar API approach

Use bulk calendar-event upsert with stable `external_id` values owned by CycleFar.

Conceptual endpoint:

```text
POST /api/v1/athlete/0/events/bulk?upsert=true
```

The Intervals.icu guide describes `external_id` as a way for external applications to upsert their own calendar events without duplicating them.

When deleting a CycleFar-owned event that no longer belongs in the next-two sync set, use the documented bulk-delete operation or event DELETE by known event id/external id.

Never delete/update calendar events that lack CycleFar's ownership marker/sync record.

## External ID

Generate once per `PlannedWorkout`, e.g.:

```text
cyclefar-workout-<uuid-or-durable-id>
```

Do not use date alone; workouts can move.

If integer DB ids are used locally, prefix them clearly to avoid collisions with other clients.

## Eligibility: “next two workouts”

Select the first two by `scheduled_on` where:

- plan is active;
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

If the live API schema differs from this example when implementation begins, adapt the serializer/client to the official API rather than changing the Rails domain model.

## Structured workout serialization

Intervals.icu supports text-based workout steps with percentage-of-FTP targets and ranges, e.g.:

```text
- Warm-up 8m ramp 45%-70%

3x
- Threshold 12m 95-100%
- Recovery 5m 50-60%

- Cool-down 7m ramp 55%-40%
```

Supported constructs documented by Intervals.icu include:

- durations such as `30s`, `10m`, `1h`;
- FTP percentages and ranges (`75%`, `95-105%`);
- ramps;
- repeat blocks;
- cue text.

The Rails domain stores expanded canonical steps. `IntervalsIcu::WorkoutSerializer` may compress obvious repeated groups into repeat syntax for readability, but correctness matters more than compression. A flat list of valid steps is acceptable if the parser supports it.

Do not send cadence targets because V1 does not prescribe cadence.

## FTP and target ranges

Use percentage-of-FTP targets in the Intervals.icu workout description rather than converting every step to absolute watts. This preserves the intended structure and matches the app's canonical model.

Send `icu_ftp`/current FTP where supported so Intervals.icu has the correct context.

## Sync reconciliation

Before sending:

1. Resolve current next-two set.
2. Load `IntervalsIcuSync` records currently associated with CycleFar-owned future workouts.
3. Build payloads and digests for next-two.
4. Upsert both.
5. Update local sync records only after successful response.
6. Remove CycleFar-owned synced calendar events that were previously in scope but have since been deleted/moved/replanned out of the next-two set, if doing so is necessary to keep Intervals.icu faithful to the explicit sync result.

A simpler acceptable V1 policy is:

- the Sync button makes Intervals.icu's *CycleFar-owned upcoming set* equal to the local next-two set;
- CycleFar-owned future events outside that set are removed;
- unrelated user events are untouched.

This makes the button's behaviour predictable.

## Partial failure

Prefer one bulk request for the two upserts when possible.

If reconciliation requires delete + upsert calls and one part fails:

- show a clear partial-sync error;
- do not corrupt local workouts;
- retain enough sync metadata to retry idempotently;
- never mark an event successfully synced until confirmed.

## Timeouts/retries

For manual V1 sync:

- use short connect/read timeouts;
- no endless retries;
- one safe retry for clearly transient network errors is acceptable;
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
