# CycleFar — External References

These references informed the initial V1 rules and integration design. They are not runtime dependencies or a current upstream-version/API verification record. Ruby/Rails versions below are repository pins, not claims about the latest available releases.

## Rails / Ruby

- Ruby on Rails releases: https://rubyonrails.org/releases
  - Repository pin: Rails 8.1.4 (`Gemfile` and `Gemfile.lock`); the initial scaffold used 8.1.3.1.
- Rails maintenance policy: https://rubyonrails.org/maintenance
- Rails 8.1 release notes: https://guides.rubyonrails.org/8_1_release_notes.html
- Ruby downloads/releases: https://www.ruby-lang.org/en/downloads/
  - Repository pin: Ruby 4.0.6 (`.ruby-version` and `Dockerfile`).

## Intervals.icu

- Open API overview: https://www.intervals.icu/features/open-api/
- Workout Builder overview: https://www.intervals.icu/features/workout-builder/
- Intervals.icu forum guide — uploading planned workouts: https://forum.intervals.icu/t/uploading-planned-workouts-to-intervals-icu/63624
- Intervals.icu forum — Workout Builder Syntax Quick Guide: https://forum.intervals.icu/t/workout-builder-syntax-quick-guide/123701
- API schema and interactive reference: https://intervals.icu/api-docs.html (loads https://intervals.icu/api/v1/docs).

Important implementation note: the public API can evolve. At implementation time, verify exact request fields/endpoints against the current Intervals.icu API documentation. Keep integration differences inside the adapter layer.

The documentation review on 2026-10-02 checked the official upload guide and public OpenAPI schema for athlete `0`, bulk upsert/delete and event field names/types. This is documentation verification, not a live authenticated sync test; see [INTERVALS_ICU.md](INTERVALS_ICU.md) for metric-unit and query-flag caveats.

## Infrastructure

- AWS public IPv4 pricing: https://aws.amazon.com/vpc/pricing/ — both in-use and idle Elastic IPs incur public IPv4 charges, checked on 2026-10-02.
- Resource-specific CloudFormation references are linked in [the infrastructure guide](../infra/cloudformation/README.md#references).

## Power zones / training metrics

- Garmin cycling training zones guide: https://www.garmin.com/en-GB/blog/cycling-training-zones-guide/
- TrainerRoad power zones calculator: https://www.trainerroad.com/power-zones-calculator
- TrainingPeaks — Normalized Power, Intensity Factor and Training Stress Score: https://www.trainingpeaks.com/learn/articles/normalized-power-intensity-factor-training-stress/
- TrainingPeaks — estimating TSS: https://www.trainingpeaks.com/learn/articles/estimating-training-stress-score-tss/

The V1 app uses a simplified five-zone model internally, while retaining Sweet Spot as a useful sub-zone/workout subtype.

## Terminology/licensing note

`Training Stress Score`, `TSS`, `Normalized Power` and related marks/algorithms are associated with TrainingPeaks/Peaksware. The live application uses the familiar training terminology requested by the product owner. This repository does not record a trademark/licensing review or permission to use those marks.
