# CycleFar — Garmin Connect Integration

## Objective

When the Garmin rider asks, import their Garmin Connect activities for the active plan's dates, show them on the calendar and link rides to completed workouts. This is Stage 1 of [ADR 0002](adr/0002-garmin-connect-activity-import.md): display only, with no effect on the training engine. The requirements are [GAR-001–GAR-013](REQUIREMENTS.md#17-garmin-connect).

**Status:** accepted, not yet built (#53–#58). The application still has ADR 0001's `WorkoutActivity` until then.

Import is manual. There is no background polling, recurring job, webhook, OAuth, business-tier access or workout push to Garmin.

**Source check:** the endpoints come from Garmin's [Personal API swagger](https://developer.garmin.com/gc-developer-program/personal/swagger-docs/) and were run against a real account on 2026-11-13 (#51). The shapes below are what that spike saw. Verify them again when building or changing the adapter, and adapt the adapter rather than the domain model.

## Enablement

- Garmin is enabled for one rider per deployment: the user whose email matches `GARMIN_RIDER_EMAIL`.
- Without the variable, or for any other rider, no Garmin UI is shown and Garmin routes return 404.
- The rider saves a **Personal API key** from the Garmin Connect Developer Program in Settings, with its expiry date. The key is encrypted with Active Record Encryption and never shown after saving.
- Settings and the import button warn at 14 days or fewer before the expiry date, and once it has passed.

## Authentication

Base URL: `https://personal.connectapi.garmin.com`.

1. Exchange the key for a token:

   ```http
   POST /personalapitoken-service/personal-api/personal-api-key/token
   Authorization: ApiKey <personal API key>
   ```

   A valid key returns `200` with a `text/plain` body holding a JWT, not JSON. The token's `exp` is 24 hours after `iat`. Neither the body nor the token carries the key's own expiry, so the rider enters it in Settings. A bad key returns `401` with an empty body.

2. Send `Authorization: Bearer <token>` on every other request.

Exchange the key once per import. Keep the token in memory for that import only; never store or cache it.

Never expose the key or token in logs, exceptions, rendered HTML, flash messages or source control.

## Endpoints

### List activities

```http
GET /activitylist-service/activities/search/activities?startDate=YYYY-MM-DD&endDate=YYYY-MM-DD&start=0&limit=<page size>
```

Returns a JSON array of activity summaries. Page with `start` (offset) and `limit`, and stop at the first page shorter than `limit`. The page size is a client constant.

Fields CycleFar uses:

| Field | Shape | Use |
| --- | --- | --- |
| `activityId` | integer, around 2.5 × 10¹⁰ | `Activity.garmin_activity_id` (bigint) |
| `activityName` | string | name |
| `activityType.typeKey` | string, e.g. `virtual_ride`, `yoga`, `strength_training` | stored raw; sport mapping |
| `activityType.typeId`, `.parentTypeId` | integers, e.g. 152 / 2 for `virtual_ride` | sport mapping (cycling is parent 2) |
| `startTimeGMT` | `"YYYY-MM-DD HH:MM:SS"`, UTC, no offset | `started_at` |
| `startTimeLocal` | `"YYYY-MM-DD HH:MM:SS"`, local, no offset | `started_on` (the local date); offset = local − GMT |
| `duration`, `elapsedDuration`, `movingDuration` | seconds, float | durations (rounded to whole seconds) |
| `distance` | metres | distance |
| `manufacturer` | string, e.g. `"ZWIFT"` | raw summary only |

Keep the whole summary object as `Activity.summary` for Stages 2 and 3. It includes `activityTrainingLoad`, best-power fields (`maxAvgPower_*`), `isPR`, heart-rate and power time-in-zone, and training-effect labels. `trainingStressScore`, `intensityFactor` and `maxFtp` are null unless the rider has an FTP in Garmin; CycleFar doesn't use them.

Third-party uploads appear in the list. Zwift rides, for example, arrive as `virtual_ride` with `manufacturer: "ZWIFT"`.

### Download the original file

```http
GET /download-service/files/activity/{activityId}
```

Returns `application/x-zip-compressed` containing one `.fit` file. The client unzips it and hands the `.fit` bytes to `Fit::Reader`. A zip that doesn't hold exactly one `.fit`, or a file `Fit::Reader` rejects, is an invalid file.

Download only for cycling activities that have no stored file. Never download a stored file again.

## Sport mapping

The adapter maps each summary to the domain `sport` enum: `cycling`, `running`, `walking`, `strength`, `yoga`, `swimming`, `other`.

- `cycling`: `activityType.parentTypeId == 2`, or the type itself is cycling. Don't list fixed type ids. The spike confirmed `virtual_ride` (parent 2); road, indoor, gravel and MTB rides are expected to share the cycling parent, so check them in fixtures as they are seen.
- Other sports map by `typeKey`: `strength_training` to `strength` and `yoga` to `yoga` were seen in the spike. Running, walking and swimming keys are mapped when first confirmed against a real payload.
- Anything else is `other`. The raw `typeKey` is always stored as `external_type`.

## Import window

- **First import:** active plan start date to today.
- **Later imports:** 7 days before the last successful import to today. The last import time is stored on the rider's profile.
- Dates are local dates (`startTimeLocal`). Activities outside the window are never touched.

## Reconciliation

For each listed activity, under an owner-scoped advisory lock:

1. **Upsert** by `garmin_activity_id`, refreshing name, type, sport, durations, distance and summary.
2. **Merge** a new Garmin activity into an uploaded activity whose UTC start is within 60 seconds: add the Garmin id, name, type and summary. The upload keeps its source, file and link.
3. **Download** the file for a cycling activity without one, then calculate its figures (see [ADR 0002](adr/0002-garmin-connect-activity-import.md#figures)). If the download or parse fails, keep the activity without a file and try again on the next import.
4. **Delete** Garmin activities stored for the window that the complete listing no longer returns. A Garmin-only record is destroyed, along with its link and file. A merged upload only loses its Garmin id and summary. If listing fails partway, delete nothing.
5. **Auto-link** rides to completed workouts ([GAR-007](REQUIREMENTS.md#gar-007-automatic-linking)).

Hold no database transaction or row lock across HTTP. Commit each activity's changes in a short transaction, so a failure keeps what was already committed and a re-run is safe.

The flash reports `Imported N, updated N, removed N`.

## Failure handling

| Failure | Response |
| --- | --- |
| `401`/`403` from the token exchange or a later call | "Your Garmin key was rejected or has expired. Update it in Settings." |
| `429` | "Garmin is rate limiting requests." Respect `Retry-After` in the message if sent. The spike saw no rate-limit headers. |
| Timeout, connection error or `5xx` | "Garmin Connect is unavailable. Try again later." |
| Invalid file | Keep the activity without a file; not a whole-import failure. |

The client raises typed errors for each case. Messages never echo Garmin's response body, the key or the token. Use short connect and read timeouts and no retries inside the request.

## Testing

Never call the real API in specs. Stub HTTP with WebMock. Fixtures are redacted spike payloads with GPS, device serials and other personal data stripped. Cover:

- the token exchange (`text/plain` JWT) and the `ApiKey`/`Bearer` headers;
- paging, including an exact-multiple final page;
- the zip download and unzip, and invalid zips and files;
- sport mapping, including the cycling parent and unknown keys;
- every error type, and that the key never appears in errors or logs;
- the import window, upsert, refresh, merge within and outside 60 seconds, deletions of Garmin-only and merged records, partial failure and re-run;
- two-rider isolation, and that completed workouts never change.
