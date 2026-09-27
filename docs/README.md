# CycleFar — V1 Build Specification

This folder is the implementation brief for **CycleFar**, a local, single-user indoor cycling training planner built with Ruby on Rails.

## Product in one sentence

**CycleFar** generates an adaptive, periodised indoor cycling training plan from a rider's goal, FTP, weekly availability and preferred workout types, then manages it through a continuous calendar and optionally syncs the next two workouts to Intervals.icu.

## V1 technology stack

- Ruby 4.0.x (pin to 4.0.6 initially)
- Rails 8.1.x (pin to 8.1.3.1 initially)
- PostgreSQL
- Hotwire: Turbo + Stimulus
- Tailwind CSS
- RSpec
- FactoryBot
- Rails built-in Active Record Encryption for the Intervals.icu API key
- No React
- Rails-generated email/password sign-in and password-reset scaffolding; no registration or per-user training ownership
- No AI/LLM in V1

CycleFar is desktop-first and intended to run locally. Separate [Terraform](../infra/README.md) and [CloudFormation](../infra/cloudformation/README.md) infrastructure preparation has since been added; it is not a deployed service, and Kamal remains a placeholder.

The authentication generator was added after the original V1 milestone sequence. Its routes now gate application requests, while Settings and training records remain shared singleton data. See [ARCHITECTURE.md](ARCHITECTURE.md) for current integration limits.

Start with [STATUS.md](STATUS.md). The [2026-09-24 review](REVIEW.md) distinguishes completed work from outstanding acceptance gaps. Historical milestone completion does not establish full requirements coverage.

## Read order for Codex

1. [`../AGENTS.md`](../AGENTS.md) — implementation rules and quality bar (after reading `STATUS.md`).
2. `PRODUCT.md` — product intent, scope and non-goals.
3. `REQUIREMENTS.md` — functional requirements and acceptance criteria.
4. `TRAINING_ENGINE.md` — deterministic planning/workout-generation rules.
5. `DATA_MODEL.md` — current Rails persistence model.
6. `ARCHITECTURE.md` — service boundaries and application structure.
7. `UX.md` — screens and interaction flows.
8. `INTERVALS_ICU.md` — integration contract.
9. `IMPLEMENTATION_PLAN.md` — build order.
10. `SOURCES.md` — external references used when writing the specification.

## Core design constraints

- There is at most one active training plan.
- Plan generation and forecasts are deterministic and rules based. Initial endurance profiles are randomly selected and persisted under WKO-009; subsequent views remain stable.
- Automatic generation structures the next 14 calendar days; later prescriptions remain outlines. Explicit Add/Copy actions and moved structures can retain detail outside that horizon.
- As each new day enters the 14-day horizon, its workout is structured automatically. Existing structured workouts are not silently regenerated.
- The user's weekly availability is a repeating Monday–Sunday template and normally uses exact durations.
- A recovery week may intentionally use less than the available duration because recovery takes priority over filling the slot.
- Workouts prescribe power as ranges of FTP and are designed for ERG mode.
- Completed workouts become immutable snapshots.
- Past planned workouts remain actionable until explicitly completed or missed.
- Plan adaptations are proposed to the rider and only applied after acceptance.
- Intervals.icu sync is explicit via a button and only syncs the next two upcoming structured workouts.

## Historical bootstrap

A reasonable initial app creation command is:

```bash
rails new cycle_far \
  --database=postgresql \
  --css=tailwind
```

Then add RSpec and FactoryBot and remove/avoid Minitest-generated tests.

The app already exists. These bootstrap commands are historical context, not the current task. Follow `STATUS.md` for current work and `../README.md` for setup and validation.

## Product naming

- Product/UI name: **CycleFar**
- Rails project/application identifier: `cycle_far` / `CycleFar`
- Owned domain: `cyclefar.com` (future deployment context only; V1 remains local)
- Keep product branding out of domain model/table names unless the name is genuinely part of an external identifier. A future rename should not require rewriting core training logic.
