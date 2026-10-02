# CycleFar C4 diagrams

These diagrams describe the implemented application, including owner-scoped requests and sync, account access, preview isolation, feedback comparisons, accepted progression bias and optional material-change replanning. They were reviewed against the controllers, services and SQL schema on 2026-10-02. They do not certify all V1 requirements; outstanding behaviour is tracked in Jira.

| View | Scope |
| --- | --- |
| [System context](cyclefar-system-context.puml) | Rider, owner-scoped CycleFar, Intervals.icu and SMTP provider |
| [Containers](cyclefar-container.puml) | Rails/Puma with supervised Solid Queue, PostgreSQL databases and SMTP provider |
| [Application components](cyclefar-component.puml) | Authentication, controlled account access, request handling, presentation, domain services and persistence |
| [Plan generation](cyclefar-plan-generation-components.puml) | Session draft, deterministic preview, confirmation, accepted bias and shared load limits during materialisation |
| [Plan changes](cyclefar-plan-change-components.puml) | Manual edits, completion, bounded feedback, before/after comparison, atomic acceptance, schedule and FTP updates |
| [Intervals.icu sync](cyclefar-intervals-icu-sync-components.puml) | Selection, serialization, HTTP calls and local reconciliation metadata |

Component views group related classes where that keeps the diagram readable. Arrows show dependencies/interactions, not a complete sequence of calls. Active Record models are application components; PostgreSQL is the database container. Completed-history protection also uses PostgreSQL triggers and constraints in `db/structure.sql`.

The UI uses server-rendered ERB and Turbo navigation/forms. Stimulus is installed but has no application-specific controller. Workout details are full pages, not modals. Horizon materialisation runs on creation, home requests and re-prescription; there is no scheduled training-generation or sync job. Initial endurance profiles are sampled and saved, while previews and explicit variations are deterministic.

The generation diagram's session component represents the Rails session draft, which is distinct from the database-backed `Session` used for login. Confirmation consumes the saved configuration and rebuilds the preview before persisting a plan. Manual Add/Copy can create structured workouts beyond the automatic 14-day horizon.

Authentication gates private application controllers, while the homepage offers registration and sign-in. Profiles, plans and sync records have required user ownership; training lookups, preview drafts and sync reconciliation use that owner. Controlled provisioning is gated, sign-out is visible, and reset/setup mail uses configured SMTP. Live SMTP delivery remains unverified; see [ACCOUNT_ACCESS.md](../ACCOUNT_ACCESS.md).

The sync view describes the current cleanup scope, which excludes linked missed/completed/past events. Remote operations and the local metadata transaction are not one atomic transaction. The plan-change view shows regular structured feedback targets in today through day 13, comparable-family fallback, nearby hard-session and difficult-easy reductions, read-only comparisons and acceptance using the same load-limited prescriptions. Accepted global bias affects later materialisation; per-family stored bias, enforced proposal expiry and full stale-input handling remain unimplemented.

AWS Terraform/CloudFormation templates are separate infrastructure preparation. They are documented in [infra/README.md](../../infra/README.md), not represented as running containers here. The container view groups the web server and its Puma-supervised Solid Queue worker into the current Kamal deployment unit. The worker delivers queued password-reset mail; it does not generate training or sync Intervals.icu.

## Rendering and maintenance

Render the six `.puml` sources with PlantUML and its layout dependencies. Each source loads C4-PlantUML from the upstream URL in its `!include`, so rendering needs access to those includes (or a locally configured copy). The upstream `master` reference is unpinned and may change rendering independently of this repository.

When updating a view, compare it with the named controllers/services, routes and persistence schema. Check relationship endpoints and render the changed views when a PlantUML runtime is available.

For a local PlantUML CLI installation, render all views into a temporary directory:

```sh
plantuml -tsvg -o /tmp/cyclefar-diagrams docs/diagrams/*.puml
```

The `.puml` files are the maintained sources; generated images are not checked in. Keep implementation limits in diagram notes and this guide aligned with [ARCHITECTURE.md](../ARCHITECTURE.md), especially after feedback or horizon changes.

Validation on 2026-10-02 rendered all six views to SVG and PNG with PlantUML 1.2026.8, downloaded C4 includes and the built-in Smetana layout engine (Graphviz was unavailable locally). All rendered views were visually reviewed, and relationship endpoints and local documentation links were checked. Default Graphviz layouts may differ.
