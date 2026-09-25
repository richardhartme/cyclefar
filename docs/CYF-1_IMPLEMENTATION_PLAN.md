# CYF-1 — Preserve plan configuration when returning from preview

Issue: [CYF-1](https://richardhartme.atlassian.net/browse/CYF-1)
Requirement: PLN-013
Milestone: 11 — Polish and hardening (acceptance follow-up)
Branch: `codex/cyf-1-preserve-preview-configuration`
Status: Implemented and validated on 2026-09-25.

## Outcome

After previewing a plan, the rider can select **Back to edit**, see their entered configuration and weekly training availability, amend it, preview again and confirm the revised plan. No plan records are created before confirmation.

## Current behaviour

- `TrainingPlansController#preview` validates permitted inputs and saves them in `session[:plan_configuration]` after building a valid preview.
- The preview's **Back to edit** link targets `new_training_plan_path`.
- `TrainingPlansController#new` always constructs `Planning::PlanConfiguration` from defaults, ignoring the saved inputs.
- `new.html.erb` already renders fields from `@configuration`, including active weekly slots.
- `#create` consumes the saved session configuration and delegates transactional persistence to `Planning::PlanCreator`.
- Existing request coverage tests preview and confirmation, but does not exercise the return-to-edit round trip.

## Implementation steps

1. **Add failing request coverage for restoration.** Extend `spec/requests/training_plan_preview_spec.rb` with PLN-013 examples that submit non-default inputs, follow the rendered **Back to edit** link and inspect form controls with Nokogiri. Assert checked radio buttons and checkboxes, selected options and input values rather than styling or incidental page text.
2. **Restore the existing session draft.** In `TrainingPlansController#new`, initialize `Planning::PlanConfiguration` from `session[:plan_configuration]` when present, falling back to `default_configuration` when absent. Read the session without consuming it so revisiting the form does not prevent confirmation. Use the existing configuration normalization and view bindings; no new route, persistence model or training-engine changes are needed.
3. **Prove edits replace the confirmed configuration.** Exercise preview → Back to edit → amend → preview → confirm. Change meaningful settings and availability, then assert the second preview and persisted plan reflect those edits, including removal of a previously active training day. Confirmation must create exactly one plan and its revised availability/event records.
4. **Cover the draft lifecycle and validation boundaries.** Verify fresh sessions use defaults, repeated edit visits retain the draft, invalid submissions render validation errors with the attempted values, and a corrected valid preview replaces the earlier session draft. Verify successful confirmation consumes the draft and a subsequent new form uses defaults. Preserve the existing behaviour that only a valid preview replaces the confirmable session configuration.
5. **Validate and record the result.** Run the checks below. Once the fix passes, update the PLN-013 entry in `docs/REVIEW.md` and add a CYF-1 completion/validation note to `docs/STATUS.md`. Keep milestone 11 open because other acceptance gaps remain. Move CYF-1 to Done only after implementation and verification are complete.

## Regression cases

| Case | Assertions |
| --- | --- |
| Non-event custom-duration plan | Goal, discipline, start date, FTP, custom weeks, Base disabled, hard/recovery mode and cycle length survive the round trip. |
| Preset duration | Selected month preset survives; a fresh session still uses the current defaults and Settings FTP. |
| Event plan | Event name/date/discipline, distance, zero elevation and expected duration survive. |
| Weekly availability | Enabled days retain exact duration and intent; rest days stay unchecked; amended availability removes disabled days and adds newly enabled days. |
| Repeated return to edit | GET requests do not consume the saved configuration. |
| Amend and confirm | Revised preview is used for creation, with the revised plan fields, availability and event details where applicable. |
| Non-persistence | Preview and edit requests do not change TrainingPlan, PlannedWorkout, WorkoutStep, PlanPhase, TargetEvent, AvailabilityTemplate or AvailabilitySlot counts. |
| Invalid then corrected preview | Invalid input returns 422 and useful errors; correcting and previewing again permits confirmation of the corrected values. |
| Draft consumed | After successful confirmation, the next configuration form uses defaults. |

Use Rails time helpers for stable dates. Compare persisted high-level configuration and prescriptions where useful; do not assert identical randomized endurance structures.

## Scope decisions

- Reopening the existing New route resumes the latest valid preview in that browser session. With no saved preview, it opens the normal defaults. This uses the current session-based flow without adding a separate draft feature.
- Weekly availability means configured training slots and rest-day selection. The current configuration object discards duration/intent values on disabled rows; retaining unused rest-day input values is outside this fix.
- Retain existing session storage and confirmation semantics. Multiple independent drafts across tabs, explicit draft reset, confirmation-failure recovery and broader session hardening are separate work.
- Existing uncommitted documentation edits were present before this task. Preserve them and keep the eventual CYF-1 patch distinguishable from those edits.

## Validation commands

Run the focused regression first, then the repository quality gates:

```bash
bundle exec rspec spec/requests/training_plan_preview_spec.rb
bundle exec rspec
bin/rails zeitwerk:check
bin/rubocop
bin/bundler-audit
bin/importmap audit
bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error
git diff --check
```

Request specs exercised non-default and event configurations through Back to edit, revised preview and confirmation, checked rendered controls and the resulting calendar. No separate browser session was run.

Validation: 1,217 RSpec examples passed; Zeitwerk passed; RuboCop passed (139 files); Brakeman reported no warnings; Bundler Audit and importmap audit found no vulnerabilities.
