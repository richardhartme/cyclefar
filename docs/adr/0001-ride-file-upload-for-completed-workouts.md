# 1. Ride file upload for completed workouts

Date: 2026-10-30
Status: Accepted

## Context

A completed workout shows the TSS, IF, NP and work that were estimated from its planned steps and frozen at completion. It does not show what was actually ridden. The rider wants a true record of the ride against the workout.

`PRODUCT.md` excludes FIT/activity ingestion and automatic completion detection from V1, and `AGENTS.md` excludes automatic ride imports. `PRODUCT.md` also lists automatic activity completion from Intervals.icu as a future-friendly seam.

Pulling activities from the Intervals.icu API was considered first and rejected for now. The rider's rides reach Intervals.icu through Strava. Intervals.icu's API withholds most data for Strava-sourced activities, so linking would return empty stats.

## Decision

The rider may upload one FIT file to a completed workout. CycleFar parses the file and shows the ride's actual figures next to the planned ones. This is a manual, per-workout upload: there is still no automatic import, activity matching or completion detection.

- **Separate record.** A new `WorkoutActivity` belongs to a completed `PlannedWorkout`, at most one per workout (unique index). It holds the attached FIT file and the calculated figures. The workout's structure, `completed_target_snapshot`, `completed_ftp_watts` and feedback are never touched. `WorkoutActivity` must not use `touch: true` or anything else that writes the parent row. The `protect_completed_workout` trigger rejects any update to a completed workout, and the new table gets no `protect_completed_workout_child` trigger, because replacing and removing the file are intended.
- **Completed workouts only.** The upload is a separate action after completion, so a failed upload never blocks completion or the feedback proposal.
- **Replace and remove.** Uploading again replaces the file and recalculates the figures. Remove deletes the file and its figures.
- **Validation.** Files are limited to 10 MB and must have a valid FIT header; the extension alone is not enough. Parsing happens during the request, and an invalid file is rejected with an error. Switch to a Solid Queue job only if parsing proves slow in practice.
- **Date mismatch.** If the ride starts on a different date from the workout's scheduled date, warn but accept. Late completion and moved rides are legitimate.
- **Figures.** Moving time, elapsed time, average power, NP (30-second rolling window), IF, TSS, kJ and average heart rate. They are calculated in the `Metrics` namespace using the workout's frozen `completed_ftp_watts`, so actual and planned figures share one FTP. A file without power data still attaches: it shows duration and heart rate, with "No power data" in place of power figures. Heart-rate-based TSS is out of scope.
- **Original file kept.** The FIT file is stored with Active Storage on the existing `cycle_far_storage` Kamal volume, so figures can be recalculated if the formula changes. This requires installing Active Storage's tables, which are not yet in `db/structure.sql`.
- **Parser.** `Fit::Reader` is a minimal in-house decoder: it checks the header, signature and CRC, reads definition and record messages (timestamp, power, heart rate, speed, enhanced speed), handles compressed timestamps and big-endian definitions, and skips developer fields by size. Rejected alternative: the `fit4ruby` gem (GPL-2.0), whose last release was July 2023 and last commit August 2024, and which pins `bindata ~> 2.4.14` while `bindata` is at 3.0.1. The decoder needs no dependency and parses a 45-minute ride in about 0.1–0.2 s.
- **Rule constants.** The moving-speed threshold (0.5 m/s) and the gap that counts as a recording pause (10 s) live in `Training::Rules` next to `NP_WINDOW_SECONDS`. Planned and ridden NP share `Metrics::NormalizedPower`, including its growing window for the first 29 samples.
- **Display only.** The detail view shows planned against actual figures. The calendar card shows actual TSS. Actual figures do not feed weekly calendar totals, load limits, feedback evaluation or adaptation proposals.
- **Ownership.** Upload, replace and remove resolve the workout through the authenticated rider's plans, like other workout actions.

## Consequences

- `PRODUCT.md`, `REQUIREMENTS.md` (a new FBK requirement), `DATA_MODEL.md`, `UX.md` and the `AGENTS.md` exclusion list are updated when the feature lands, because those documents describe the application as built.
- Specs cover the metrics calculator and parser against fixture FIT files in `spec/fixtures` (with GPS data stripped), completed-snapshot immutability, and upload/replace/remove/invalid-file/two-rider request flows.
- Feeding actual load into weekly totals or the training engine, day-level aggregation of several rides, and Intervals.icu activity import remain future decisions.
