# CycleFar — External References

These references informed the initial V1 rules and integration design. They are not runtime dependencies.

## Rails / Ruby

- Ruby on Rails releases: https://rubyonrails.org/releases
  - As checked 5 September 2026, Rails 8.1.3.1 is the latest listed 8.1 security patch release.
- Rails maintenance policy: https://rubyonrails.org/maintenance
- Rails 8.1 release notes: https://guides.rubyonrails.org/8_1_release_notes.html
- Ruby downloads/releases: https://www.ruby-lang.org/en/downloads/
  - As checked 5 September 2026, Ruby 4.0.6 is the current stable release shown by ruby-lang.org.

## Intervals.icu

- Open API overview: https://www.intervals.icu/features/open-api/
- Workout Builder overview: https://www.intervals.icu/features/workout-builder/
- Intervals.icu forum guide — uploading planned workouts: https://forum.intervals.icu/t/uploading-planned-workouts-to-intervals-icu/63624
- Intervals.icu forum — Workout Builder Syntax Quick Guide: https://forum.intervals.icu/t/workout-builder-syntax-quick-guide/123701

Important implementation note: the public API can evolve. At implementation time, verify exact request fields/endpoints against the current Intervals.icu API documentation. Keep integration differences inside the adapter layer.

## Power zones / training metrics

- Garmin cycling training zones guide: https://www.garmin.com/en-GB/blog/cycling-training-zones-guide/
- TrainerRoad power zones calculator: https://www.trainerroad.com/power-zones-calculator
- TrainingPeaks — Normalized Power, Intensity Factor and Training Stress Score: https://www.trainingpeaks.com/learn/articles/normalized-power-intensity-factor-training-stress/
- TrainingPeaks — estimating TSS: https://www.trainingpeaks.com/learn/articles/estimating-training-stress-score-tss/

The V1 app deliberately exposes only a simplified five-zone model internally, while retaining Sweet Spot as a useful sub-zone/workout subtype.

## Terminology/licensing note

`Training Stress Score`, `TSS`, `Normalized Power` and related marks/algorithms are associated with TrainingPeaks/Peaksware. For a personal local V1 this spec uses the familiar training terminology requested by the product owner. Before commercial/public release, review trademark/licensing implications and consider product-neutral labels such as `planned load` if appropriate.
