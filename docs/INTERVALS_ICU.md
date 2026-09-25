# CycleFar — Intervals.icu Integration

## V1 objective

On explicit rider action, sync the next two upcoming structured cycling workouts from the active plan to the rider's Intervals.icu calendar.

No automatic sync, activity import, completion detection, OAuth or webhook handling in V1.

The request details below describe the implemented adapter as reviewed on 2026-09-24, not a new live-API certification. Local specs stub HTTP. See [REVIEW.md](REVIEW.md) for reconciliation gaps.

## Authentication

Use the rider's personal API key from Intervals.icu Settings. The client uses HTTP Basic auth with username `API_KEY` and the key as password.

Intervals.icu documents API-key authentication and allows athlete id `0` to mean the authenticated athlete. Keep athlete-id assumptions isolated in the client so OAuth/multi-rider support can be added later.

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

The client deletes by external ID using `PUT /api/v1/athlete/0/events/bulk-delete` with a JSON array such as `[{"external_id":"cyclefar-workout-123"}]`. It does not list or search unrelated remote events.

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

When changing the adapter, verify the upstream API schema and adapt this boundary rather than changing the Rails domain model. The payload above matches the current serializer; its metric units have not been revalidated against the live API in this documentation review.

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
2. Build payloads with stable external IDs and bulk-upsert the set.
3. Find stale local sync records: detached records, plus records for still-planned future workouts in this plan that are no longer in the selected set.
4. Bulk-delete those stale external IDs.
5. After both remote operations succeed, transactionally save returned event IDs, digests and timestamps, then destroy stale local sync records.

Digests are stored for reference; repeat sync still upserts both selected workouts. Deleted local workouts leave detached sync records via a nullable foreign key, allowing later cleanup.

The intended policy is that CycleFar's owned upcoming remote set matches the next-two set, with unrelated events untouched. Current reconciliation does not include linked missed/completed workouts or workouts moved into the past; those stale-event cases remain open in REVIEW.md.

## Partial failure

Prefer one bulk request for the two upserts when possible.

If reconciliation requires delete + upsert calls and one part fails:

- show a clear partial-sync error;
- do not corrupt local workouts;
- retain enough sync metadata to retry idempotently;
- never mark an event successfully synced until confirmed.

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
