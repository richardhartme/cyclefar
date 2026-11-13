# 2. Garmin Connect activity import

Date: 2026-11-13
Status: Accepted. Partly supersedes [ADR 0001](0001-ride-file-upload-for-completed-workouts.md) on the activity source, the `WorkoutActivity` model and the rule that rides never move between workouts.

## Context

ADR 0001 lets the rider upload one FIT file to a completed workout. Every ride still has to be exported and uploaded by hand, and nothing the rider does outside CycleFar's workouts (other rides, runs, strength sessions) is visible.

The rider's rides reach Intervals.icu through Strava or Garmin. Intervals.icu withholds Strava-sourced data from its API and is stopping passing Garmin data to third-party apps, so it can't be the activity source. Garmin reopened its Connect Developer Program on 21 October 2026 with a self-service **Personal API** for a user's own data. It pulls on demand by date range, returns activity summaries and can download the original file.

A spike against a real account (#51, 2026-11-13) confirmed:

- **Token.** `POST /personalapitoken-service/personal-api/personal-api-key/token` with the Personal API key returns `200` with a `text/plain` JWT. It expires 24 hours after issue. Neither the response nor the token carries the key's own expiry date. A bad key gets `401` with an empty body. No rate-limit headers were seen.
- **List.** `GET /activitylist-service/activities/search/activities` on `https://personal.connectapi.garmin.com`, with `startDate`, `endDate`, `start` and `limit`, and `Authorization: Bearer <token>`, lists activities. Rides have `activityType.parentTypeId == 2` (for example `virtual_ride`, typeId 152). Yoga and strength training share parent 29.
- **Shapes.** `activityId` is an integer around 2.5 × 10¹⁰. Durations are seconds (float), distance is metres. `startTimeLocal` and `startTimeGMT` are `YYYY-MM-DD HH:MM:SS` with no offset.
- **Third-party uploads appear**, for example Zwift rides (`manufacturer: "ZWIFT"`).
- **Garmin's `trainingStressScore`, `intensityFactor` and `maxFtp` are null** when no FTP is set in Garmin. `activityTrainingLoad`, best-power fields (`maxAvgPower_*`), `isPR`, heart-rate and power time-in-zone, and training-effect labels are present.
- **File.** `GET /download-service/files/activity/{id}` returns `application/x-zip-compressed` holding one `.fit` file, which `Fit::Reader` parses. CycleFar's figures matched Garmin's closely (NP 158.0 against 158.4 W, moving time 2,706 against 2,700 s).

This is Stage 1 of three. Stage 2 (actual load feeding planning) and Stage 3 (rule-based insights per activity) each need their own ADR. Stage 1 stores what they will need: sport, Garmin's summary and the ride files.

## Decision

CycleFar imports the rider's Garmin Connect activities on demand, shows them on the calendar and links rides to completed workouts. Stage 1 is display only. Completion stays manual.

### Source and access

- **Garmin Connect Personal API only.** No business-tier application, OAuth, webhooks or Intervals.icu activity import. Pushing planned workouts to Intervals.icu (ICU-001) is unchanged.
- **One Garmin rider per deployment.** Garmin is enabled only for the user whose email matches the `GARMIN_RIDER_EMAIL` environment variable. Without it, or for anyone else, no Garmin UI is shown and Garmin routes return 404. Self-hosters use their own key.
- **Key in Settings.** The Garmin rider stores their Personal API key in Settings, encrypted with Active Record Encryption like the Intervals.icu key and never shown after saving. Because Garmin doesn't return the key's expiry, the rider enters the expiry date too. Settings and the import button warn at 14 days or fewer before expiry and once it has passed. Clearing the key disables imports and keeps imported activities.
- **Token per import.** Each import exchanges the key for a 24-hour token, held in memory only and never stored.
- **Isolation.** HTTP lives under `GarminConnect::`, like `IntervalsIcu::`. The key never appears in logs, exceptions or rendered output. Specs never make real network calls.
- FIT upload stays available to every rider.

### Data model

`WorkoutActivity` becomes a rider-owned **`Activity`**, superseding ADR 0001's "separate record that belongs to a completed workout":

- It belongs to a `User`, not a workout, and survives plan archival or deletion.
- It records its source (`garmin` or `upload`), the Garmin activity id (bigint, unique per rider), a mapped `sport` plus the raw Garmin type key, the name, the start time in UTC and the local date it started on, durations, distance, figures, Garmin's raw summary (`jsonb`) and, for cycling only, the original FIT file.
- It **links to at most one completed workout**, and a workout has at most one activity. The database enforces both, and that a link points at a completed workout of the same rider. The link records whether it was made automatically or by the rider.
- **Relinking replaces ADR 0001's "never move" rule.** A ride can move from one completed workout to another in one transaction. The completed workout's structure, snapshot, metrics and feedback are still never written.
- Archiving a plan keeps its completed workouts and their links as history. Nothing nulls a link on archive: completed workouts are immutable history, and the next plan's import window starts at its own start date, so archived rides are never touched.

### Times and dates

- `startTimeGMT` gives the UTC start time. `startTimeLocal` gives the local date the activity is scheduled on, which matching and the calendar use. The UTC offset is their difference.
- An uploaded FIT file keeps ADR 0001's behaviour: its local date comes from the start time in the application time zone.

### Sport mapping

The adapter maps Garmin types to the domain `sport` enum: `cycling`, `running`, `walking`, `strength`, `yoga`, `swimming`, `other`.

- **Cycling** is any activity whose `activityType.parentTypeId` is 2, or whose own type is cycling. It doesn't depend on fixed type ids, so road, indoor, virtual, gravel and MTB rides all count.
- Other sports map by type key (for example `strength_training` to `strength`, `yoga` to `yoga`). Unknown keys map to `other`. The raw key is always stored.

### Figures

- **Cycling** figures come from the original file through `Fit::Reader` and `Metrics::RideCalculator`, as in ADR 0001. Garmin's TSS and IF are not used: they are null unless Garmin has an FTP, and CycleFar's FTP is the one that matters.
  - A linked ride uses the workout's frozen `completed_ftp_watts`.
  - An unlinked ride uses the FTP in force on its local date, from FTP history: the newest reading on or before that date, with the highest id winning a tie. A ride before the first reading uses the earliest reading.
  - Figures are recalculated from the stored file on link, unlink and relink, and when the FTP history changes the reading that applies.
- **Other sports** show duration, distance and heart rate from the summary. Garmin's `activityTrainingLoad` is stored in the summary, not shown.
- A ride without power data shows duration and heart rate with "No power data", as in ADR 0001.

### Import

- **Manual only.** An "Import from Garmin" button sits in the calendar header next to "Sync to Intervals.icu". It is shown only to the Garmin rider, only with an active plan and a saved key. The import runs in the foreground request. Background polling and recurring jobs stay out of scope.
- **Window.** The first import runs from the active plan's start date to today. Later imports run from 7 days before the last successful import to today. The last import time is stored on the rider. Activities outside the window are never touched.
- **Upsert.** Activities are keyed by Garmin activity id. A changed summary refreshes the stored fields.
- **Files.** The original file is downloaded only for cycling activities that don't have one yet. A stored file is never downloaded again. If a download or parse fails, the activity is kept without a file, shows its summary duration and heart rate, and the next import tries again.
- **Duplicates.** Two activities starting within 60 seconds of each other are one ride, whichever arrives first. An imported Garmin activity matching an upload is merged into it: the upload gains the Garmin id, name, type and summary, and keeps its source, link and file. An uploaded file matching an unlinked activity links that activity instead of creating a second record, keeping its stored file or taking the upload if it has none. A match already linked to another workout rejects the upload with guidance to use Change ride.
- **Deletions.** After a complete listing, a Garmin activity that is stored for the window but no longer returned is treated as deleted. A Garmin-only record is removed, with its link and file. A merged record keeps its file and link and only loses the Garmin id and summary. A failed or partial listing deletes nothing.
- **Concurrency.** An owner-scoped advisory lock stops two imports racing. No database transaction is held across HTTP. A failure keeps what was committed before it and is safe to re-run.
- **Result.** A flash reports the counts imported, updated and removed, or readable guidance for a bad or expired key, rate limiting (respecting `Retry-After` if Garmin sends it) and Garmin being unavailable.

### Matching

- Only `cycling` activities are candidates.
- **Auto-link.** A completed workout with no link and exactly one unlinked cycling activity on its scheduled date is linked automatically, at two moments only: on completion, and after an import for the activities that import created. A ride the rider unlinked is never new to a later import, so it is never auto-linked again, with no extra state to store. Auto-link never replaces an existing link.
- **Choose ride.** A completed workout with no link and none or several candidates shows "Choose ride". The picker lists cycling activities within 3 days either side of the scheduled date, newest first: unlinked rides, plus rides linked to other completed workouts in the active plan, labelled with that workout. Choosing a linked ride asks for confirmation, then relinks it in one transaction. Rides linked in archived plans are history and are not offered.
- **Upload over a Garmin link.** A workout with a Garmin ride linked offers Change ride and Unlink instead of Upload; a direct upload is rejected with "Unlink the Garmin ride first."
- **Unlink** is available on any link. For an uploaded activity it removes the activity and its file, as ADR 0001's remove does.
- **Ride found.** A `planned` workout with an unlinked cycling activity on its date shows "Ride found — mark this workout completed?". It opens the normal completion form (RPE and quality) with that ride preselected, and links it on completion. **Nothing completes automatically.**
- Two rides on one day stay separate. A workout links at most one; the other shows as its own calendar entry.

### Calendar

- Unlinked activities appear as compact secondary entries under the day's card, including on days without a workout. They show sport, name, duration and TSS when power is present, and open a read-only detail view.
- A linked ride appears only on its workout card, never as a second entry.
- Only dates inside the active plan's calendar range show activities.
- Each activity shows a plain source label: "Garmin Connect" or "Uploaded FIT", following its `source`.

### No engine effect in Stage 1

Weekly totals, load limits, feedback evaluation, adaptation proposals, missed-workout handling and workout statuses ignore activities. The training engine is unchanged.

## Consequences

- `REQUIREMENTS.md` gains the `GAR-*` requirements and an FBK-004 rewrite. `PRODUCT.md`, `DATA_MODEL.md`, `ARCHITECTURE.md`, `UX.md`, `TRAINING_ENGINE.md`, `AGENTS.md`, the README and the diagrams describe Stage 1. [`GARMIN_CONNECT.md`](../GARMIN_CONNECT.md) records the API contract.
- The work is split across #53 (the `Activity` model), #54 (client), #55 (enablement and key), #56 (import), #57 (matching) and #58 (calendar display). Until they land, the application still has ADR 0001's `WorkoutActivity`.
- Imported activities, including Garmin files on the `cycle_far_storage` volume, become rider data worth backing up.
- Only one rider per deployment can use Garmin. Supporting more needs a Garmin business-tier application and a new ADR.
- "Automatic ride imports" stays excluded in `AGENTS.md` until a background job is decided.
- Stage 2 (load-aware planning) and Stage 3 (rule-based insights, no LLM) each need their own ADR and design session.
