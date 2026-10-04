# CycleFar architecture diagrams

These diagrams describe the implemented application, including owner-scoped requests and sync, account access, preview isolation, feedback comparisons, accepted progression bias and optional material-change replanning. The views reflect changes through CYF-14 and were reviewed on 2026-10-04, including shared recovery scheduling, ranked FTP assessments, staged taper budgets, return-stage power limits, canonical calendar summaries and complete tracked-event reconciliation. They do not certify all V1 requirements; outstanding behaviour is tracked in Jira.

| View (PlantUML source) | PNG | Scope |
| --- | --- | --- |
| [System context](context-cyclefar-system.puml) | [PNG](png/context-cyclefar-system.png) | Rider, owner-scoped CycleFar, Intervals.icu and SMTP provider |
| [Containers](container-cyclefar.puml) | [PNG](png/container-cyclefar.png) | Rails/Puma with supervised Solid Queue, PostgreSQL databases and SMTP provider |
| [Application components](component-cyclefar-application.puml) | [PNG](png/component-cyclefar-application.png) | Authentication, account access, canonical calendar summaries, domain services and persistence |
| [Plan generation](component-cyclefar-plan-generation.puml) | [PNG](png/component-cyclefar-plan-generation.png) | Session draft, aligned recovery, ranked assessments, taper budgets, confirmation and saved generation choices during materialisation |
| [Plan changes](component-cyclefar-plan-change.puml) | [PNG](png/component-cyclefar-plan-change.png) | Manual edits, completion, bounded feedback, atomic acceptance, comparable pre-break progression, staged return limits and FTP updates |
| [Intervals.icu sync](component-cyclefar-intervals-icu-sync.puml) | [PNG](png/component-cyclefar-intervals-icu-sync.png) | Selection, serialization, pre-upload identities, confirmed metadata and all owned stale-event cleanup |

The component views answer **which parts own a responsibility**. For request order and read/write boundaries, follow the sequence views:

| Sequence view (PlantUML source) | PNG | Follow this flow |
| --- | --- | --- |
| [Create a plan](sequence-cyclefar-plan-creation.puml) | [PNG](png/sequence-cyclefar-plan-creation.png) | Review an owner-bound preview with shared scheduling and taper budgets; confirm, persist generation choices and materialize the 14-day horizon. |
| [Change future training](sequence-cyclefar-future-replanning.puml) | [PNG](png/sequence-cyclefar-future-replanning.png) | Rebuild affected prescriptions with assessment exclusions, taper context and comparable pre-break return limits, then materialize nearby detail. |
| [Feedback proposal](sequence-cyclefar-feedback-proposal.puml) | [PNG](png/sequence-cyclefar-feedback-proposal.png) | Completion saves an immutable snapshot; feedback creates an optional proposal; read-only comparison precedes acceptance or rejection. |
| [Material Change Workout proposal](sequence-cyclefar-material-change-proposal.puml) | [PNG](png/sequence-cyclefar-material-change-proposal.png) | Change Workout immediately saves the selected workout; a separate optional acceptance replans the bounded following block. |
| [Manual Intervals.icu reconciliation](sequence-cyclefar-intervals-icu-sync.puml) | [PNG](png/sequence-cyclefar-intervals-icu-sync.png) | Retain identities before upload, save confirmed metadata, clean every stale owned event, and preserve retry metadata on failure. |

Read the [application component view](component-cyclefar-application.puml) for orientation, then the sequence that matches the rider action. The two proposal sequences are separate because feedback proposes edits to upcoming workouts, while a material Change Workout has already saved its source workout before the optional replan is offered.

Component views group related classes where that keeps the diagram readable. Arrows show dependencies/interactions, not a complete sequence of calls. Active Record models are application components; PostgreSQL is the database container. Completed-history protection also uses PostgreSQL triggers and constraints in `db/structure.sql`.

The UI uses server-rendered ERB and Turbo navigation/forms. Stimulus is installed but has no application-specific controller. Workout details are full pages, not modals. Horizon materialisation runs on creation, home requests and re-prescription; opening or completing a due/overdue executable outline materialises only that source; there is no scheduled training-generation or sync job. Initial endurance profiles are sampled and saved, while previews and explicit variations are deterministic.

The generation diagram's session component represents the Rails session draft, which is distinct from the database-backed `Session` used for login. Confirmation consumes the saved configuration and rebuilds the preview before persisting a plan. Manual Add/Copy can create structured workouts beyond the automatic 14-day horizon.

Authentication gates private application controllers, while the homepage offers registration and sign-in. Profiles, plans and sync records have required user ownership; training lookups, preview drafts and sync reconciliation use that owner. Controlled provisioning is gated, sign-out is visible, and reset/setup mail uses configured SMTP. Live SMTP delivery remains unverified; see [ACCOUNT_ACCESS.md](../ACCOUNT_ACCESS.md).

The sync views show reconciliation of every tracked event owned by the rider outside the next-two set, including missed/completed, past-moved, deleted and previous-plan workouts. Owned identities are saved before HTTP; confirmed uploads are saved before cleanup. An uncertain upload retains its identities, while cleanup failure retains both confirmed upload metadata and stale identities for retry. Remote operations and local transactions are separate. Completed local history and remote activities remain unchanged (CYF-14).

The plan-change view shows regular structured feedback targets in today through day 13, comparable-family fallback, nearby hard-session and difficult-easy reductions, read-only comparisons and acceptance using the same load-limited prescriptions. ProposalCreator saves a seven-day deadline and a digest of relevant canonical inputs. ProposalFreshness enforces expiry, active-plan status and unchanged relevant prescriptions/schedule/load before comparison and acceptance; stale, expired or unverifiable proposals offer dismissal. FTP-only metric recalculation does not invalidate them. Acceptance applies the exact load-limited canonical definition shown in the comparison and rolls back all edits if any step fails. Accepted global bias affects later materialisation; per-family stored bias remains unimplemented.

AWS Terraform/CloudFormation templates are separate infrastructure preparation. They are documented in [infra/README.md](../../infra/README.md), not represented as running containers here. The container view groups the web server and its Puma-supervised Solid Queue worker into the current Kamal deployment unit. The worker delivers queued password-reset mail; it does not generate training or sync Intervals.icu.

Ordinary and missed Move share `Workouts::Mover` and `DestinationValidator`. Eligible same-context moves of at most seven days keep their structure; other moves regenerate from destination progression, retaining subtype and duration. Destination exclusions and weekly load warnings apply to both paths. Openers record immutable completion feedback without progression adaptation; late regular-workout feedback is suppressed only when the next scheduled workout is completed.

`WeeklyLoadCap` and `LoadReduction` enforce the ordered section 27 strategy during previews, actual materialisation and feedback comparisons/acceptance: progression level, lower-load variation, work targets within existing bands, compatible subtype reduction for broad Intervals, then valid short main sets plus easy filler. Normal duration, specific subtype intent and sampled endurance profile identity remain fixed. Generation choices survive outline persistence; infeasible schedules show a non-blocking warning after valid options are exhausted. Partial, recovery, taper, assessment, time-off and re-entry weeks do not become comparable hard-week references. Manual one-off overrides retain separate automatic-load references.

`RecoverySchedule` supplies the same flags to `PlanBuilder`, `CalendarPresenter` and `LoadContext`. A recovery within one week of a Build/Speciality transition can align to the preceding complete Monday–Sunday week; at least one hard week separates recoveries and the cycle resumes from the aligned week. Taper weeks are excluded; continuous progression adds no scheduled recoveries.

`AssessmentSchedule` ranks configured intensity days, including specific subtypes, within the four-to-six-week window: first intensity after recovery, first intensity near a phase start, rest/recovery-preceded intensity, then other intensity and ordinary-day fallbacks. Ties use distance from the ideal five-week date and then the earlier date. If the whole window is unavailable, it uses the first later eligible slot. Recovery and taper are excluded; `ExistingPlanConfiguration` also excludes time off and return ramps before selection. The 14-day end exclusion applies to target events, not non-event plans. Short plans retain the no-routine-assessment policy.

After hard-week load enforcement, `PlanBuilder` budgets taper stages against the highest comparable generated hard-week TSS. A long taper's earlier stage targets 75% of peak, prorated by its days; the final seven dates through the event target 50%, including for non-Sunday events. Early/final intensity work factors are 75%/60%, retaining normal power bands and positive 30-second segments. Duration adjusts toward the budget without adding training dates; the 30-minute minimum, event and opener remain fixed, so sparse availability can make the approximate target infeasible. Saved `load_adjustments.main_set_factor` and fitted progression ceilings survive outline persistence, horizon generation and post-break recalculation; positive bias cannot escalate saved tapered sets. Legacy taper outlines retain the level-2 ceiling fallback. The change does not bulk rewrite existing plans.

`PreBreakProgression` selects the latest planned/completed regular session in the comparable intensity family, excluding missed and special records and defaulting to level 1. `ReturnRamp` applies 60/70/80/100% duration factors with the 30-minute minimum; first/second-stage main targets are 45–60%/55–68% FTP, then level-1 Tempo on intensity days or Endurance on easy days. The final stage returns to the scheduled subtype one level below the baseline, with weekly progression resuming from that reduced level after the ramp. Holiday/Event/Other resume from the baseline without the reduction. `TargetBandLimiter` constrains main targets and caps every step endpoint; saved return bands/stages survive profile sampling and materialisation. Proposal freshness uses the same comparable baseline (CYF-12).

`CalendarHelper` derives repeated main/activation summaries and watt ranges from canonical steps, including separate under/over efforts and ramp endpoints. Planned cards use current owner FTP; completed cards use frozen per-step watts. Views show TSS/IF/work, outline purpose and supplied event distance/elevation/duration. These summaries remain presentation, never training inputs (CYF-13).

## Rendering and maintenance

The `.puml` files are the maintained sources; PNG exports live in [`png/`](png/). Regenerate the PNG whenever its source changes. The source filenames determine export filenames, and all six C4 views use PlantUML's built-in Smetana layout engine, so Graphviz is not required.

The C4 sources load C4-PlantUML from the upstream URL in their `!include`, so rendering those views needs access to those includes (or a locally configured copy). The five sequence sources are self-contained. The upstream `master` reference is unpinned and may change C4 rendering independently of this repository.

With a local PlantUML CLI installation, run from the repository root:

```sh
plantuml -nometadata -tpng -o png docs/diagrams/*.puml
```

With a standalone JAR, use:

```sh
java -Djava.awt.headless=true -DPLANTUML_LIMIT_SIZE=16384 -jar /path/to/plantuml.jar -nometadata -tpng -o png docs/diagrams/*.puml
```

PlantUML resolves this relative output directory beside each source, producing `docs/diagrams/png/<source-name>.png`. Use `-tsvg` instead of `-tpng` and a temporary output directory for SVG inspection. `-nometadata` keeps rendering-source metadata out of PNGs.

When updating a view, compare it with the named controllers/services, routes and persistence schema. Check relationship endpoints, render the sources and inspect the resulting images. Keep implementation limits in diagram notes and this guide aligned with [ARCHITECTURE.md](../ARCHITECTURE.md), especially after proposal, move, completion or horizon changes.

Validation on 2026-10-04 rendered all eleven views to PNG and temporary SVG with PlantUML 1.2026.8, the previously downloaded C4 includes and the built-in Smetana layout engine. The exports were checked for rendering errors and visually reviewed; source/PNG links were checked.
