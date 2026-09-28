# CycleFar Product Specification

## Vision

**CycleFar** is a focused indoor cycling training planner that gives the rider control over *when* and *what kind* of training they do, while the application handles periodisation, workout construction, progression and adaptation.

CycleFar sits between a static training plan and a full virtual cycling platform. It does not run the trainer. Its value is creating and maintaining a coherent plan around the rider's real availability.

## Primary user

The original V1 release was a single-rider planner. Email/password sign-in and self-registration are now implemented locally, and the public home offers both paths. Profiles, plans and Intervals.icu sync records have required user ownership in PostgreSQL, training controller lookups are owner-scoped, and FTP-based services use the owning plan. Preview drafts and sync reconciliation are owner-scoped. Controlled account provisioning, SMTP configuration and automated two-rider coverage are also implemented. Deployment with additional riders still requires the target-data migration rehearsal, live mail check and Milestone 11 acceptance work.

The assumed rider:

- knows their FTP;
- trains indoors using ERG mode;
- wants structured power-based workouts;
- wants to choose which days are intensity/endurance/recovery days;
- wants the application to decide the precise workout progression;
- may be training generally or toward one target event.

## Jobs to be done

The rider should be able to:

1. Tell the app what they are training for.
2. Tell it when they can train and what type of session each day should contain.
3. Get a periodised plan with sensible load progression.
4. See the entire plan in one continuous calendar.
5. See detailed, executable workouts for the next 14 days.
6. Change a workout when life or motivation changes without destroying the whole plan.
7. Record simple post-workout feedback and receive optional adaptations.
8. Plan holidays, illness and recovery into the schedule.
9. Update FTP and have future wattage targets change automatically.
10. Push the next two workouts to Intervals.icu on demand.

## Training goals

V1 supports exactly these top-level goals:

- General Fitness
- Increase FTP
- Improve Endurance
- Improve Climbing
- Prepare for an Event

## Cycling disciplines

The rider chooses one discipline during plan setup:

- Road
- Gravel
- MTB
- Ultra / Endurance

Discipline has limited impact in Base, more impact in Build, and the strongest impact in Speciality.

## Product principles

### Rider-controlled schedule

The rider chooses training days, exact normal duration and broad/specific session intent. The engine should not rearrange intensity days behind the rider's back.

### Engine-controlled workout progression

The rider should not need to decide whether today's threshold session is 3x8, 4x8 or 3x12. The deterministic workout engine makes that decision from phase, progression state and feedback.

### Stable plans, not constant churn

The plan should not silently regenerate every time anything changes. Adaptation is targeted and visible. Proposed changes require acceptance.

### Near-term specificity, long-term flexibility

Only the next 14 days are fully structured. The rest of the plan stores purpose/type/duration/phase so future detailed workouts can reflect newer FTP and feedback.

### Explain important changes

Whenever the engine proposes an adaptation or replans a block, present a concise explanation of what is changing and why.

## V1 scope

### Included

This describes intended V1 scope, including later additions. See [STATUS.md](STATUS.md) and [REVIEW.md](REVIEW.md) for implementation gaps.

- Email/password registration, sign-in, sign-out and password reset
- Settings with FTP and Intervals.icu API key
- One active training plan
- One target event maximum
- Plan creation + preview + confirmation
- Continuous Monday-first calendar
- Base / Build / Speciality / Taper phases
- Optional Base phase
- Continuous progression or configurable hard-week/recovery-week cycle
- Rule-based plan generation
- Fully structured upcoming workouts
- Planned TSS, IF and work estimates
- Weekly totals and weekly load progression
- Manual workout completion + RPE + completion quality
- Optional adaptation proposals
- Workout shuffle/change/move/copy and adding a workout to an empty date
- Persistent missed-workout calendar status and a weekly TSS chart
- Schedule changes for one week or from a date onward
- Time off: holiday, illness, recovery, event, other
- Return-to-training ramp after illness/recovery
- FTP assessment recommendations
- Intervals.icu sync for next two workouts

### Explicitly out of scope

- Enabling additional riders before the release gate
- Coaches/social features
- Running, strength or multisport training
- Controlling a smart trainer
- Recording ride data
- FIT/activity ingestion
- Automatic completion detection
- Automatic notifications/reminders
- Cadence targets
- Heart-rate targets
- Workout notes
- Editing individual interval steps
- Drag-and-drop calendar editing
- Calendar filters/legend
- Separate history screen
- Multiple active plans
- Multiple target events
- AI-generated plans or workouts
- Hosted-service operation (separate infrastructure preparation is described below)

## Planned independent-rider release

Milestone 12 is planned after the open Milestone 11. Its ownership schema, owner-scoped application paths, public registration, controlled provisioning and automated two-rider matrix have been implemented locally, but the deployment release gate remains open. Each `User` owns one rider profile, at most one active plan, and any number of archived plans retained as history. Training records and FTP readings follow their owning plan or profile. Each rider's Intervals.icu credentials, sync records and remote reconciliation stay within that rider's account, including sync records detached from deleted workouts. A plan preview created in one browser account cannot be viewed or confirmed after another account signs in there. The target database copy rehearsal and live SMTP delivery remain unverified; operator provisioning remains disabled by default.

The first independent-rider release excludes Google or other social sign-in, coaches, shared plans and teams. It does not add a separate History screen. Existing single-rider data will be assigned only to an explicitly selected existing account after a preflight; ambiguous ownership must stop the migration. See [REQUIREMENTS.md](REQUIREMENTS.md#16-planned-independent-rider-release) for the acceptance and test contract.

## Future-friendly seams

Do not implement these now, but avoid architecture that blocks them:

- importing training history/current volume;
- experience level and age as planning inputs;
- automatic activity completion from Intervals.icu;
- AI assistance layered above deterministic rules;
- mobile-first UI;
- trainer execution;
- OAuth for Intervals.icu;
- custom zone models;
- drag-and-drop calendar interaction.

## Brand / naming

- Canonical product name: **CycleFar**.
- Domain owned by the project: `cyclefar.com`. The V1 application remains local. Separate Terraform and CloudFormation templates now prepare a possible AWS deployment; no deployed service is recorded. See [infrastructure documentation](../infra/README.md).
- User-facing copy should call the application **CycleFar**, not generic names such as “Cycling Trainer App”.
- Do not couple persistence/domain classes to the brand name; concepts should remain `TrainingPlan`, `PlannedWorkout`, etc.
