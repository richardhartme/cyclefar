# CycleFar architecture diagrams

These diagrams describe the implemented application, including owner-scoped requests and sync, account access, preview isolation, feedback comparisons, accepted progression bias and optional material-change replanning. All ten views were reviewed against the controllers, services and SQL schema on 2026-10-03, including proposal freshness, destination-aware moves, executable completion and ordered weekly load-cap enforcement through CYF-10. They do not certify all V1 requirements; outstanding behaviour is tracked in Jira.

| View (PlantUML source) | PNG | Scope |
| --- | --- | --- |
| [System context](context-cyclefar-system.puml) | [PNG](png/context-cyclefar-system.png) | Rider, owner-scoped CycleFar, Intervals.icu and SMTP provider |
| [Containers](container-cyclefar.puml) | [PNG](png/container-cyclefar.png) | Rails/Puma with supervised Solid Queue, PostgreSQL databases and SMTP provider |
| [Application components](component-cyclefar-application.puml) | [PNG](png/component-cyclefar-application.png) | Authentication, controlled account access, request handling, presentation, domain services and persistence |
| [Plan generation](component-cyclefar-plan-generation.puml) | [PNG](png/component-cyclefar-plan-generation.png) | Session draft, deterministic preview, confirmation, accepted bias and shared load limits during materialisation |
| [Plan changes](component-cyclefar-plan-change.puml) | [PNG](png/component-cyclefar-plan-change.png) | Manual edits, completion, bounded feedback, before/after comparison, atomic acceptance, schedule and FTP updates |
| [Intervals.icu sync](component-cyclefar-intervals-icu-sync.puml) | [PNG](png/component-cyclefar-intervals-icu-sync.png) | Selection, serialization, HTTP calls and local reconciliation metadata |

The component views answer **which parts own a responsibility**. For request order and read/write boundaries, follow the sequence views:

| Sequence view (PlantUML source) | PNG | Follow this flow |
| --- | --- | --- |
| [Create a plan](sequence-cyclefar-plan-creation.puml) | [PNG](png/sequence-cyclefar-plan-creation.png) | Submit and review an owner-bound, in-memory preview; confirm, persist outlines and materialize the 14-day horizon. |
| [Change future training](sequence-cyclefar-future-replanning.puml) | [PNG](png/sequence-cyclefar-future-replanning.png) | Availability, time-off or missed-workout replan enters `FuturePrescriber`, replaces affected future prescriptions and materializes nearby detail. |
| [Feedback proposal](sequence-cyclefar-feedback-proposal.puml) | [PNG](png/sequence-cyclefar-feedback-proposal.png) | Completion saves an immutable snapshot; feedback creates an optional proposal; read-only comparison precedes acceptance or rejection. |
| [Material Change Workout proposal](sequence-cyclefar-material-change-proposal.puml) | [PNG](png/sequence-cyclefar-material-change-proposal.png) | Change Workout immediately saves the selected workout; a separate optional acceptance replans the bounded following block. |

Read the [application component view](component-cyclefar-application.puml) for orientation, then the sequence that matches the rider action. The two proposal sequences are separate because feedback proposes edits to upcoming workouts, while a material Change Workout has already saved its source workout before the optional replan is offered.

Component views group related classes where that keeps the diagram readable. Arrows show dependencies/interactions, not a complete sequence of calls. Active Record models are application components; PostgreSQL is the database container. Completed-history protection also uses PostgreSQL triggers and constraints in `db/structure.sql`.

The UI uses server-rendered ERB and Turbo navigation/forms. Stimulus is installed but has no application-specific controller. Workout details are full pages, not modals. Horizon materialisation runs on creation, home requests and re-prescription; opening or completing a due/overdue executable outline materialises only that source; there is no scheduled training-generation or sync job. Initial endurance profiles are sampled and saved, while previews and explicit variations are deterministic.

The generation diagram's session component represents the Rails session draft, which is distinct from the database-backed `Session` used for login. Confirmation consumes the saved configuration and rebuilds the preview before persisting a plan. Manual Add/Copy can create structured workouts beyond the automatic 14-day horizon.

Authentication gates private application controllers, while the homepage offers registration and sign-in. Profiles, plans and sync records have required user ownership; training lookups, preview drafts and sync reconciliation use that owner. Controlled provisioning is gated, sign-out is visible, and reset/setup mail uses configured SMTP. Live SMTP delivery remains unverified; see [ACCOUNT_ACCESS.md](../ACCOUNT_ACCESS.md).

The sync view describes the current cleanup scope, which excludes linked missed/completed/past events. Remote operations and the local metadata transaction are not one atomic transaction. The plan-change view shows regular structured feedback targets in today through day 13, comparable-family fallback, nearby hard-session and difficult-easy reductions, read-only comparisons and acceptance using the same load-limited prescriptions. ProposalCreator saves a seven-day deadline and a digest of relevant canonical inputs. ProposalFreshness enforces expiry, active-plan status and unchanged relevant prescriptions/schedule/load before comparison and acceptance; stale, expired or unverifiable proposals offer dismissal. FTP-only metric recalculation does not invalidate them. Acceptance applies the exact load-limited canonical definition shown in the comparison and rolls back all edits if any step fails. Accepted global bias affects later materialisation; per-family stored bias remains unimplemented.

AWS Terraform/CloudFormation templates are separate infrastructure preparation. They are documented in [infra/README.md](../../infra/README.md), not represented as running containers here. The container view groups the web server and its Puma-supervised Solid Queue worker into the current Kamal deployment unit. The worker delivers queued password-reset mail; it does not generate training or sync Intervals.icu.

Ordinary and missed Move share `Workouts::Mover` and `DestinationValidator`. Eligible same-context moves of at most seven days keep their structure; other moves regenerate from destination progression, retaining subtype and duration. Destination exclusions and weekly load warnings apply to both paths. Openers record immutable completion feedback without progression adaptation; late regular-workout feedback is suppressed only when the next scheduled workout is completed.

`WeeklyLoadCap` and `LoadReduction` enforce the ordered section 27 strategy during previews, actual materialisation and feedback comparisons/acceptance: progression level, lower-load variation, work targets within existing bands, compatible subtype reduction for broad Intervals, then valid short main sets plus easy filler. Normal duration, specific subtype intent and sampled endurance profile identity remain fixed. Generation choices survive outline persistence; infeasible schedules show a non-blocking warning after valid options are exhausted. Partial, recovery, taper, assessment, time-off and re-entry weeks do not become comparable hard-week references. Manual one-off overrides retain separate automatic-load references.

## Rendering and maintenance

The `.puml` files are the maintained sources; PNG exports live in [`png/`](png/). Regenerate the PNG whenever its source changes. The source filenames determine export filenames, and all six C4 views use PlantUML's built-in Smetana layout engine, so Graphviz is not required.

The C4 sources load C4-PlantUML from the upstream URL in their `!include`, so rendering those views needs access to those includes (or a locally configured copy). The four sequence sources are self-contained. The upstream `master` reference is unpinned and may change C4 rendering independently of this repository.

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

Validation on 2026-10-03 rendered all ten views to PNG and temporary SVG with PlantUML 1.2026.8, the previously downloaded C4 includes and the built-in Smetana layout engine. The exports were checked for rendering errors and visually reviewed; source/PNG links were checked.
