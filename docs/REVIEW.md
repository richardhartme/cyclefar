# Implementation review — 2026-09-24

Reviewed the committed application at `a3a2310` against all supporting Markdown documents and six PlantUML sources in `docs/`, using routes, models, migrations, services, views, specs and recent history. The working tree was clean at the start. This review changes documentation only.

The implementation contains all original milestone slices and several later additions, but it does not meet every documented acceptance criterion. Milestone 11 is reopened for hardening and acceptance follow-up. Requirements below remain authoritative; documenting a gap does not waive it.

## Confirmed later additions

- No-plan calendar, weekly TSS chart, power-zone graph colours and expanded workout detail styling.
- Retained missed-workout status, copying regular structured workouts, adding workouts on empty dates and selecting an Opener manually.
- Event time-off reason, optional time-off names and re-prescription respecting later availability templates.
- Persisted random endurance profiles, deterministic forecasts and descriptive variation keys. Migration preserves legacy keys in completed history.
- Production database environment configuration and separate Terraform/CloudFormation infrastructure preparation. No deployed service is recorded; Kamal remains a placeholder.

These changes are reflected in PRODUCT, REQUIREMENTS, TRAINING_ENGINE, DATA_MODEL, ARCHITECTURE, UX and STATUS. The original bootstrap prompt and milestone plan are labelled historical.

CYF-1 resolved PLN-013 on 2026-09-25: Back to edit now restores the saved preview configuration. Request coverage checks edit, revised preview, confirmation and non-persistence before confirmation.

CYF-2 resolved WKO-005 on 2026-09-26: a material Change Workout action now creates an optional persisted proposal. Acceptance keeps the changed workout fixed and atomically re-prescribes the bounded following 14-day block using the effective availability template for each date; dismissal preserves the remaining plan.

## Open acceptance gaps

These are findings from source inspection, not newly added failing regression tests. Existing green tests do not establish complete requirement coverage. Address each with focused coverage before closing it.

| Area | Intended behaviour | Current evidence and follow-up |
|---|---|---|

| FBK-002: proposal review | Show affected workouts and before/after values. | [`FeedbackEvaluator`](../app/services/adaptations/feedback_evaluator.rb) stores IDs and target levels; the [calendar](../app/views/home/index.html.erb) shows only the reason and Accept/Reject. Add reviewable before/after details. |
| FBK-002, GEN-001; engine §§12, 32, 47 | Accepted progression bias affects later generation. | [`ProposalApplier`](../app/services/adaptations/proposal_applier.rb) saves global `intensity_bias`; [`HorizonMaterializer`](../app/services/planning/horizon_materializer.rb) uses the outline level directly and does not read that state. The saved bias therefore does not affect newly materialised workouts. |
| FBK-002; engine §§29–31 | Bound adaptations to 14 days, support comparable-family fallback and nearby hard-session reductions. | [`FeedbackEvaluator`](../app/services/adaptations/feedback_evaluator.rb) finds only the next same-subtype structured workout, without an upper date bound. Add/Copy/Move can leave structured workouts beyond 14 days. It proposes one target only and does not recheck the weekly cap. Easy-workout levels can be nil, so arithmetic on the target level also needs coverage for high-RPE Recovery/Endurance feedback. |
| Proposal expiry/staleness | Refuse stale changes and expire proposals. | [`ProposalApplier`](../app/services/adaptations/proposal_applier.rb) checks planned/structured status but not `expires_at`, prior structure or schedule changes. Completion sets an expiry which is currently not enforced. |
| WKO-006, MIS-001; engine §35 | Regenerate moved workouts when phase changes or the move exceeds seven days. | The [controller move](../app/controllers/planned_workouts_controller.rb) and [`MissedWorkoutResolver#move!`](../app/services/planning/missed_workout_resolver.rb) update date/phase only. They do not regenerate or refresh destination load warnings. |
| OFF-001 and event calendar | Keep normal workouts off time-off/target-event dates. | [`Creator`](../app/services/workouts/creator.rb) rejects both kinds of date, but [Move](../app/controllers/planned_workouts_controller.rb), [`Copier`](../app/services/workouts/copier.rb) and missed Move only check plan bounds/collisions. The model does not provide the missing exclusions. |
| FBK-001 and late completion | Executable workouts remain completable. | [`CompletionRecorder`](../app/services/adaptations/completion_recorder.rb) and the [detail view](../app/views/planned_workouts/show.html.erb) only support regular structured workouts; openers cannot be completed. A past outline that never entered a visited horizon also has no completion path because materialisation starts today. |
| LOAD-002; engine §27 | Apply the full ordered load-reduction strategy and validate actual generated load. | [`PlanBuilder#lower_week_load`](../app/services/planning/plan_builder.rb) lowers progression levels only, then warns; variation/target/subtype/filler fallback is absent. Random endurance materialisation and accepted adaptations do not recheck the cap against actual metrics. |
| Engine §§8, 41, 44 | Recovery alignment near phase boundaries, ranked FTP-test placement and staged taper treatment. | [`PlanBuilder`](../app/services/planning/plan_builder.rb) uses a fixed recovery cycle, ranks FTP candidates by broad Intervals intent then proximity to day 35, and applies one reduced intensity session plus easy rides throughout taper. The more detailed documented ranking/alignment and two-stage long taper are not implemented. FTP tests are also excluded from the final 14 days of non-event plans. |
| OFF-001; engine §39 | Enforce return-stage power bands as well as durations. | [`FuturePrescriber`](../app/services/planning/future_prescriber.rb) selects standard Recovery/Endurance generators and 60/70/80/100% duration factors. It does not supply the documented second-stage 55–68% target band; endurance profiles can reach 74%. Pre-break level uses the maximum historical level rather than the most recent comparable session. |
| CAL-002, PLN-022 | Show prescribed card detail and optional event metadata. | The [calendar view](../app/views/home/index.html.erb) omits structured-card main-set summaries, target ranges and kJ; outlines omit purpose; target events show name/discipline but omit optional distance, elevation and duration. |
| ICU-001: reconciliation | Remove owned upcoming events that leave the next-two set. | [`SyncNextTwo#reconciled_syncs`](../app/services/intervals_icu/sync_next_two.rb) includes detached records and linked planned future workouts only. Marking a synced workout missed/completed or moving it into the past can leave a stale remote event. Retain enough prior sync scope to reconcile these transitions. |

## Presentation and reporting follow-up

- UX recommends a Turbo Frame modal and replacement/availability previews. Current detail/actions are full-page forms and redirects; those preferred interactions have not been implemented.
- [`CalendarPresenter#weeks`](../app/services/planning/calendar_presenter.rb) includes missed records in duration/TSS/work totals and the chart. MIS-001 specifies retention but does not define how missed load contributes to totals. Decide the reporting meaning before changing this calculation.
- The [workout step view](../app/views/planned_workouts/show.html.erb) contains a malformed closing list-item tag (`</liv`), and the change/move/copy/completion controls need a browser accessibility review. Green request specs do not establish valid rendered markup or keyboard usability.
- The calendar renders Add Workout links on padding dates outside plan bounds, though the service rejects those dates. Align link eligibility with the service.

## Validation performed

On 2026-09-24:

- `bundle exec rspec`: **1,213 examples, 0 failures**.
- `bin/rails zeitwerk:check`: passed.
- `bin/rubocop`: **139 files, no offenses**.
- `bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error`: no warnings or errors.
- `bin/bundler-audit`: no vulnerabilities reported.
- `bin/importmap audit`: no vulnerable packages reported.

All 53 local Markdown links resolved, whitespace checks passed, and all six PlantUML sources passed document-marker and relationship-reference checks. No application code was changed, so no new behavioural tests were added. No browser acceptance walkthrough, PlantUML rendering, live Intervals.icu contract check, upstream release verification or AWS deployment/validation was performed in this review. Infrastructure validation history remains in STATUS.md.

## Next work

Use milestone 11 to close the acceptance gaps above, prioritising progression/adaptation correctness, completion paths, schedule exclusions and remote reconciliation. Add regression coverage for each fix, then repeat the repository quality gates and the relevant browser flows before declaring V1 fully accepted. This review does not authorise changing the specified training constants or expanding the product scope.
