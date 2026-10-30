# CycleFar architecture diagrams

Thirteen PlantUML diagrams of the implemented application. They show structure and flow; they don't certify every V1 requirement. For the behaviour behind them, see [ARCHITECTURE.md](../ARCHITECTURE.md).

## Component views

Which parts own a responsibility. Arrows show dependencies, not call order.

| View (source) | PNG | Scope |
| --- | --- | --- |
| [System context](context-cyclefar-system.puml) | [PNG](png/context-cyclefar-system.png) | Rider, CycleFar, Intervals.icu and the SMTP provider |
| [Containers](container-cyclefar.puml) | [PNG](png/container-cyclefar.png) | Rails/Puma with Solid Queue, PostgreSQL, ride file storage and SMTP |
| [Application components](component-cyclefar-application.puml) | [PNG](png/component-cyclefar-application.png) | Authentication, account access, calendar, domain services, ride files and persistence |
| [Plan generation](component-cyclefar-plan-generation.puml) | [PNG](png/component-cyclefar-plan-generation.png) | Preview draft, recovery alignment, taper budgets, confirmation and materialisation |
| [Plan changes](component-cyclefar-plan-change.puml) | [PNG](png/component-cyclefar-plan-change.png) | Manual edits, completion, feedback proposals, schedule changes, return ramps and FTP updates |
| [Intervals.icu sync](component-cyclefar-intervals-icu-sync.puml) | [PNG](png/component-cyclefar-intervals-icu-sync.png) | Owner lock, eligibility, serialization, reconciliation, FTP refresh and plan-removal cleanup |

## Sequence views

Request order and read/write boundaries for one rider action.

| View (source) | PNG | Flow |
| --- | --- | --- |
| [Create a plan](sequence-cyclefar-plan-creation.puml) | [PNG](png/sequence-cyclefar-plan-creation.png) | Preview, confirm, persist, then materialise the 14-day horizon |
| [Change future training](sequence-cyclefar-future-replanning.puml) | [PNG](png/sequence-cyclefar-future-replanning.png) | Availability, time-off and missed-workout replans, per effective template |
| [Feedback proposal](sequence-cyclefar-feedback-proposal.puml) | [PNG](png/sequence-cyclefar-feedback-proposal.png) | Completion, optional proposal, read-only comparison, then accept or reject |
| [Material Change Workout proposal](sequence-cyclefar-material-change-proposal.puml) | [PNG](png/sequence-cyclefar-material-change-proposal.png) | Change Workout saves immediately; an optional proposal replans the following block |
| [Make a workout Easier/Harder](sequence-cyclefar-directional-adjustment.puml) | [PNG](png/sequence-cyclefar-directional-adjustment.png) | Pick the next ladder level or profile that moves TSS the right way, or report the limit |
| [Upload, replace or remove a ride file](sequence-cyclefar-ride-file-upload.puml) | [PNG](png/sequence-cyclefar-ride-file-upload.png) | Parse the FIT file outside the lock, then save ridden metrics beside completed history |
| [Manual Intervals.icu reconciliation](sequence-cyclefar-intervals-icu-sync.puml) | [PNG](png/sequence-cyclefar-intervals-icu-sync.png) | Save identities, upload, confirm, clean up stale events, keep retry metadata on failure |

Start with the application component view, then open the sequence for the action you care about. The two proposal sequences are separate because feedback proposes edits to upcoming workouts, whereas Change Workout has already saved its workout before the replan is offered.

## Conventions

- Component views group related classes to stay readable. Active Record models are application components; PostgreSQL is the database container.
- The "session" in the plan-generation view is the Rails session draft, not the database `Session` used for login.
- AWS infrastructure (Terraform/CloudFormation) is documented in [infra/README.md](../../infra/README.md), not drawn here.
- Diagram notes record implementation limits; keep them in step with [ARCHITECTURE.md](../ARCHITECTURE.md).

## Rendering

The `.puml` files are the sources; PNGs live in [`png/`](png/) and must be regenerated whenever a source changes. With `plantuml` on your `PATH`:

```sh
docs/diagrams/generate-pngs.sh
```

The script runs from any directory, checks every source first, writes PNGs without embedded metadata, and exits non-zero on failure without writing error images. `PLANTUML_LIMIT_SIZE` defaults to 16384.

With a standalone JAR instead:

```sh
java -Djava.awt.headless=true -DPLANTUML_LIMIT_SIZE=16384 -jar /path/to/plantuml.jar -nometadata -tpng -o png docs/diagrams/*.puml
```

The six C4 views use PlantUML's built-in Smetana layout (no Graphviz needed) and `!include` C4-PlantUML from its unpinned upstream `master`, so rendering needs network access and the styling can change upstream. The seven sequence views are self-contained.

When updating a view, check it against the named controllers, services, routes and schema, then render it and inspect the image.
