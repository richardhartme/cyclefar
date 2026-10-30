# CycleFar Product Specification

## Vision

**CycleFar** is a focused indoor cycling training planner that gives the rider control over *when* and *what kind* of training they do, while the application handles periodisation, workout construction, progression and adaptation.

CycleFar sits between a static training plan and a full virtual cycling platform. It does not run the trainer. Its value is creating and maintaining a coherent plan around the rider's real availability.

## Primary user

Riders self-register and sign in with email and password. All their data is owned by their account (see [Independent riders](#independent-riders)).

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
10. Push all upcoming structured workouts to Intervals.icu on demand.

Changing FTP also refreshes future workouts already synced to Intervals.icu. If that refresh fails, the FTP change still stands and the rider is told to retry with Sync. First exports and stale-event cleanup only happen on demand.

## Training goals

V1 supports exactly these top-level goals:

- General Fitness
- Increase FTP
- Improve Endurance
- Improve Climbing
- Prepare for an Event

## Cycling disciplines

For Prepare for an Event, the rider chooses one Event discipline during plan setup:

- Road
- Gravel
- MTB
- Ultra / Endurance

The discipline sets the broad Intervals mix in Build and Speciality; Base uses a generic cycle. Explicitly chosen weekly subtypes keep their intent, subject to the normal reduced-load overrides.

Non-event goals have no discipline choice. New non-event plans store an internal `road` default that doesn't affect training.

## Product principles

### Rider-controlled schedule

The rider chooses training days, exact normal duration and broad/specific session intent. The engine should not rearrange intensity days behind the rider's back.

### Engine-controlled workout progression

The rider should not need to decide whether today's threshold session is 3x8, 4x8 or 3x12. The deterministic workout engine makes that decision from phase, progression state and feedback.

### Stable plans, not constant churn

The plan should not silently regenerate every time anything changes. Adaptation is targeted and visible. Proposed changes require acceptance.

Feedback proposals show each affected workout before and after, at the rider's current FTP, and only target the next 14 days. An accepted intensity bias applies to later workouts as they become structured. Proposals expire after seven days and are rejected if their inputs have changed; stale ones can be dismissed. The bias is global; per-family bias is not implemented (see [ARCHITECTURE.md](ARCHITECTURE.md#completion-adaptations-and-schedule-changes)).

### Near-term specificity, long-term flexibility

Workouts get detailed steps from today through day 13. Later workouts store only type, duration, phase, purpose and forecast load, so their detail can reflect newer FTP and feedback. Add, Copy, Move and completing a due or overdue outline can create detail outside that window.

### Explain important changes

Whenever the engine proposes an adaptation or replans a block, present a concise explanation of what is changing and why.

## V1 scope

### Included

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
- Optional FIT ride file upload on a completed workout, showing ridden against planned metrics
- Optional adaptation proposals
- Workout shuffle/change/move/copy and adding a workout to an empty date
- Persistent missed-workout calendar status and a weekly TSS chart
- Schedule changes for one week or from a date onward
- Time off: holiday, illness, recovery, event, other
- Return-to-training ramp after illness/recovery
- Intervals.icu sync for all upcoming structured workouts

### Explicitly out of scope

- Coaches/social features
- Running, strength or multisport training
- Controlling a smart trainer
- Recording ride data
- Activity import from Intervals.icu, Strava or other services (a manually uploaded FIT file per completed workout is supported)
- Automatic completion detection or matching rides to workouts
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

## Independent riders

Each `User` owns one rider profile, at most one active plan and any number of archived plans. Workouts, FTP readings, Intervals.icu credentials and sync records all belong to that rider, and a plan preview can't be viewed or confirmed by another account signing in on the same browser. Operator provisioning is disabled until live mail delivery is verified (see [ACCOUNT_ACCESS.md](ACCOUNT_ACCESS.md)).

There is no social sign-in, no coaches, shared plans or teams, and no separate History screen. See [REQUIREMENTS.md](REQUIREMENTS.md#16-independent-riders) for the acceptance and test contract.

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
- The application is live at `cyclefar.com`; see the [README](../README.md#deployment) and [infrastructure documentation](../infra/README.md).
- User-facing copy should call the application **CycleFar**, not generic names such as “Cycling Trainer App”.
- Do not couple persistence/domain classes to the brand name; concepts should remain `TrainingPlan`, `PlannedWorkout`, etc.
