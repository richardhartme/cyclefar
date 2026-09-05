# CycleFar

A local, single-rider indoor cycling training planner. Task 01 implements the
application foundation and core persistence (Milestones 0 and 1 in
[the implementation plan](docs/IMPLEMENTATION_PLAN.md)).

## Local setup

Requirements: Ruby **4.0.6**, Rails **8.1.3.1** (locked by Bundler), and a running
PostgreSQL **17+** server with its client tools (`psql`, `pg_dump`) on PATH.
The local PostgreSQL role must be able to create development and test databases.
If socket defaults do not match your installation, use `PGHOST`, `PGPORT`,
`PGUSER`, and `PGPASSWORD`.

```sh
rbenv install -s 4.0.6
bin/setup --skip-server
bin/dev
```

Visit <http://localhost:3000>. Home links to Settings and a plan-creation
placeholder. Save your FTP in Settings; no default FTP is invented. The API key
is optional. `bin/dev` runs Puma and the Tailwind watcher; its generated launcher
installs Foreman if needed. Alternatively, after setup, use `bin/rails server`.

`bin/setup` installs dependencies, generates private local encryption keys,
prepares the databases, and builds Tailwind. It is safe to rerun without
replacing encryption keys. The app uses Turbo, Stimulus, and Tailwind with
import maps; Node is not required.

## API-key storage

Active Record Encryption stores the Intervals.icu key as ciphertext. Local keys
live in ignored `config/active_record_encryption.*.key` files with mode `0600`.
Keep these files with any database backup: replacing or losing them prevents
decryption of existing API keys. No API key is returned in HTML or model
inspection, and request parameters are filtered from logs.

The corresponding environment variables can override local keys:

- `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`
- `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY`
- `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT`

Rails encrypted credentials under `active_record_encryption` are also supported
when no override is supplied. Tests use isolated, test-only keys.

A blank API-key field preserves the stored key. Enter a replacement or select
`Remove saved API key` to clear it. No Intervals.icu HTTP client exists yet.

## Persistence conventions

- The singleton profile has ID 1, enforced by PostgreSQL. Settings writes go
  through `Settings::Update`, which saves FTP history in the same transaction
  and serializes concurrent saves. Direct model writes do not create history.
- Availability uses ISO weekdays: Monday=1 through Sunday=7. Missing slots are
  rest days. Application dates use the London timezone and Monday-first weeks.
- All 13 models from `docs/DATA_MODEL.md` are present. `FtpReading` additionally
  references the singleton profile. Two migrations create the schema and protect
  completed history. The schema is stored as `db/structure.sql` so PostgreSQL
  triggers survive schema loads.
- Unique indexes enforce one active plan, one workout per plan/date, and the
  specified one-to-one relationships. Models validate domain enums, dates,
  ranges, canonical steps, and completion snapshot prerequisites.
- Completed workouts, steps and feedback reject edits/deletion, including bulk
  writes. Parent plans containing completed workouts cannot be destroyed.
  The later completion service must save steps/feedback and then mark the
  workout completed in one transaction. No completion workflow is implemented.
- A structured workout must have steps totaling its duration when saved.
  Full plan assembly validation and workout generation belong to later milestones.

Routes: `GET /`, `GET /settings`, `PATCH/PUT /settings`,
`GET /training_plan/new` (placeholder), and the existing `GET /up` health check.

## Checks

```sh
bundle exec rspec
bin/rails zeitwerk:check
bin/rubocop
bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error
bin/bundler-audit
bin/importmap audit
```

`bin/ci` runs setup and these checks. GitHub Actions includes PostgreSQL-backed
RSpec and autoload checks alongside the existing lint and security jobs.

Milestone 2 adds the pure deterministic workout engine: versioned target
constants, progression ladders, exact-duration generation, metrics and workout
profile data. Plan configuration, preview, calendar, completion/adaptation,
schedule changes, sync and realistic generated demo plans remain deferred to
their documented milestones. There is no authentication or new deployment
infrastructure.
