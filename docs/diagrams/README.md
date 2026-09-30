# CycleFar C4 diagrams

Training flows were reviewed against application source through 2026-09-28, including owner-scoped requests and sync, account access, same-browser preview isolation and optional material-change replanning. These diagrams describe the implemented application while additional rider provisioning remains gated. They do not certify all V1 requirements; outstanding behaviour is tracked in [REVIEW.md](../REVIEW.md).

| View | Scope |
| --- | --- |
| [System context](cyclefar-system-context.puml) | Rider, owner-scoped CycleFar and the external Intervals.icu service |
| [Containers](cyclefar-container.puml) | Rails application, PostgreSQL and configured SMTP provider |
| [Application components](cyclefar-component.puml) | Authentication, controlled account access, request handling, presentation, domain services and persistence |
| [Plan generation](cyclefar-plan-generation-components.puml) | Session draft, deterministic preview, confirmation and request-driven materialisation |
| [Plan changes](cyclefar-plan-change-components.puml) | Manual edits, completion, proposals, schedule changes and FTP updates |
| [Intervals.icu sync](cyclefar-intervals-icu-sync-components.puml) | Selection, serialization, HTTP calls and local reconciliation metadata |

Component views group related classes where that keeps the diagram readable. Arrows show dependencies/interactions, not a complete sequence of calls. Active Record models are application components; PostgreSQL is the database container. Completed-history protection also uses PostgreSQL triggers and constraints in `db/structure.sql`.

The UI uses server-rendered ERB and Turbo navigation/forms. Stimulus is installed but has no application-specific controller. Workout details are full pages, not modals. Horizon materialisation runs on creation, home requests and re-prescription; there is no scheduled training-generation or sync job. Initial endurance profiles are sampled and saved, while previews and explicit variations are deterministic.

The generation diagram's session component represents the Rails session draft, which is distinct from the database-backed `Session` used for login. Confirmation consumes the saved configuration and rebuilds the preview before persisting a plan. Manual Add/Copy can create structured workouts beyond the automatic 14-day horizon.

Authentication gates private application controllers, while the homepage offers registration and sign-in. Profiles, plans and sync records have required user ownership; training lookups, preview drafts and sync reconciliation use that owner. Controlled provisioning is gated, sign-out is visible, and reset/setup mail uses configured SMTP. Live SMTP delivery remains unverified; see [ACCOUNT_ACCESS.md](../ACCOUNT_ACCESS.md).

The sync view describes the current cleanup scope, which excludes some stale linked events. Remote operations and the local metadata transaction are not one atomic transaction. The plan-change view shows the implemented material Change proposal and records saved-but-unused progression bias and incomplete feedback-proposal bounds/expiry; see [REVIEW.md](../REVIEW.md) for the full acceptance backlog.

AWS Terraform/CloudFormation templates are separate deployment preparation, with no deployed environment recorded. They are documented in [infra/README.md](../../infra/README.md), not represented as running containers here. Rails production cache/queue/cable database configuration does not imply separate implemented training workers.

## Rendering and maintenance

Render the six `.puml` sources with PlantUML and its layout dependencies. Each source loads C4-PlantUML from the upstream URL in its `!include`, so rendering needs access to those includes (or a locally configured copy). The upstream `master` reference is unpinned and may change rendering independently of this repository.

When updating a view, compare it with the named controllers/services, routes and persistence schema. Check relationship endpoints and render the changed views when a PlantUML runtime is available. The 2026-09-25 review checked document structure and relationship references locally; visual rendering was not performed because PlantUML is not installed in this workspace.
