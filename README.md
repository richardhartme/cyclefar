# CycleFar

CycleFar is a local, single-rider cycling training planner. It turns a rider's
goal, availability, FTP and target event into a deterministic training plan,
then keeps the calendar practical as training is completed, missed or changed.

The application is desktop-first and designed around a continuous weekly
calendar. Workout targets are stored as percentages of FTP, so future workouts
can adapt when FTP changes while completed workouts retain their historical
snapshots.

## What it includes

- Guided plan creation with a preview for general fitness, FTP, endurance,
  climbing and event goals.
- Rails-generated email/password sign-in, sign-out and password-reset scaffolding.
- A deterministic, versioned workout engine for endurance, tempo, Sweet Spot,
  threshold, VO2 max, over-under and recovery sessions.
- A continuous calendar with workout details, editable future workouts and
  inline power-profile graphs.
- Completion feedback, overdue and missed-workout resolution, and explicit
  adaptation proposals.
- Availability changes, planned time off and a gradual return after illness or
  recovery time.
- FTP history and recalculation of future workout watt targets without changing
  completed workouts.
- Manual Intervals.icu sync for the next two executable structured workouts.
  CycleFar only reconciles events that it owns.
- Archive and delete controls for a plan, plus an idempotent development seed
  for visual testing.

CycleFar currently enables one rider. Profiles, plans, preview drafts and
Intervals.icu sync records are scoped to the signed-in user, and an integrated
two-rider test matrix exercises those boundaries. Additional rider provisioning
remains disabled until the target database migration rehearsal, live mail
delivery and open Milestone 11 acceptance work are complete. There is no public
registration. V1 has no ride imports, trainer control, notifications or
automatic calendar syncing.

## Local setup

CycleFar requires Ruby **4.0.6**, Bundler and a running PostgreSQL **17+**
server with `psql` and `pg_dump` on `PATH`. Your local PostgreSQL role must be
able to create the development and test databases. Set `PGHOST`, `PGPORT`,
`PGUSER` and `PGPASSWORD` if your PostgreSQL installation needs them.

```sh
rbenv install -s 4.0.6
bin/setup --skip-server
bin/dev
```

Open <http://localhost:3000>. `bin/setup` installs dependencies, creates local
Active Record Encryption keys, prepares the database and builds Tailwind CSS.
It can be rerun safely; existing encryption keys are retained. Use
`bin/setup --reset` when a local database reset is wanted.

The encryption-key files in `config/` are ignored by Git. Keep them with any
local database backup: losing them prevents decryption of a saved Intervals.icu
API key.

Prepare the database, then open the homepage and choose **Register** to create
your rider account or **Sign In** if you already have one. The checked-in
`db/structure.sql` includes authentication and user ownership constraints.
Production password-reset delivery uses environment-configured SMTP; delivery
through a live provider has not been verified. See the [account access
guide](docs/ACCOUNT_ACCESS.md) for deployment settings and the release gate.

## Development sample plan

In development, load a realistic 12-week plan with a 260 W FTP and a
Tuesday/Thursday/Saturday/Sunday schedule:

```sh
CYCLEFAR_SEED_USER_EMAIL=rider@example.com bin/rails db:seed
```

Set the email to an existing local user. The seed is idempotent for that user and does nothing when they already have an active plan.

## Working with Intervals.icu

Save an Intervals.icu API key in **Settings**, then use the calendar's manual
sync action. Sync exports only the next two structured workouts that can be
performed and uses stable `cyclefar-` external IDs. It neither imports rides nor
changes unrelated Intervals.icu events.

## Validation

```sh
bundle exec rspec
bin/rails zeitwerk:check
bin/rubocop
bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error
bin/bundler-audit
bin/importmap audit
```

`bin/ci` runs the configured continuous-integration checks.

## Documentation

- [Product overview](docs/PRODUCT.md)
- [Requirements](docs/REQUIREMENTS.md)
- [Training-engine rules](docs/TRAINING_ENGINE.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Data model](docs/DATA_MODEL.md)
- [UX guide](docs/UX.md)
- [Implementation status](docs/STATUS.md)
