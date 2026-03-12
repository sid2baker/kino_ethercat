# EtherCAT Introduction

This folder now holds the Livebook teaching material for the simulator-first introduction path.
The first two phases are now merged into one simple notebook.

The objective is still the same: create an excellent introduction to EtherCAT for newcomers with as little setup friction as possible. The simulator should be the default environment, real hardware should be optional, and the material should teach EtherCAT itself before it teaches this library or Elixir.

## Implemented Now

- [Phases 1 and 2: EtherCAT Introduction](./01_ethercat_introduction.livemd)

These two phases are also reflected in the generated `Introduction` tab from the `EtherCAT Simulator` smart cell.

## Current Teaching Workspace

The main entrypoint is now the `EtherCAT Simulator` smart cell plus the generated `Introduction` tab:

1. Add the `EtherCAT Simulator` smart cell.
2. Keep or rename the default `coupler -> inputs -> outputs` ring.
3. Click `Auto-wire matching signals`.
4. Evaluate the generated code.
5. Start in the `Introduction` tab.

That workspace now gives you:

- a guided learning path
- a reduced teaching-mode UI instead of the full operator layout
- short explanations next to master state and domain/WKC health
- a clear handoff from the simulator ring to setup/discovery and OP activation

Use the `EtherCAT Setup` smart cell against the same simulator when you want to move from the virtual ring into discovery, PREOP readiness, and OP activation.

## Core Vision

The curriculum should help a new reader answer these questions in order:

1. What problem is EtherCAT solving?
2. What are the fundamental moving parts of an EtherCAT system?
3. What does cyclic process-data exchange actually feel like?
4. What do the important runtime states mean?
5. What does failure look like on a live EtherCAT network?
6. Why is a live, interactive, process-oriented environment useful here?
7. Why does Elixir become a compelling fit once the protocol model is understood?

The key design rule is that the reader should first build an operational mental model of EtherCAT, then develop intuition through interactive experiments, and only after that see how `kino_ethercat` and Elixir support that workflow.

There should not be a separate "scenario livebooks" track inside this introductory material. Faults, recovery, multidomain behavior, and other advanced topics should appear as deliberate steps in the same learning sequence.

## Audience

Primary audience:

- engineers who have heard of EtherCAT but have not used it directly
- developers who know software well but not industrial fieldbuses
- controls or automation engineers who want a fast way to explore concepts interactively

Secondary audience:

- readers evaluating whether Elixir is a reasonable tool for device orchestration, observability, or fault-tolerant control systems

The material should assume curiosity and technical literacy, but not EtherCAT experience.

## Non-Goals

- Do not start with `kino_ethercat` feature tours.
- Do not front-load Beckhoff-specific or hardware-bench-specific details.
- Do not begin with DC, mailbox internals, or multidomain scheduling.
- Do not make readers fight setup before they have seen a single useful behavior.
- Do not require the reader to understand Elixir syntax before understanding EtherCAT concepts.

## Teaching Principles

- Simulator first. The first meaningful result should happen without hardware.
- Concepts before APIs. Explain protocol behavior before naming library helpers.
- One idea per step. Each lesson should answer one main question well.
- Visible causality. Every action should produce an observable change in state, data, timing, or faults.
- Progress from concrete to abstract. Let readers see bits move before discussing architecture.
- Keep terminology disciplined. Introduce terms only when their behavior can be observed.
- Separate normal operation from fault analysis. Readers need a stable baseline before debugging enters the picture.
- Defer implementation advocacy. Elixir should show up as a response to demonstrated needs, not as a premise.

## Learning Outcomes

After the introductory path, a reader should be able to:

- describe master, slave, PDO, domain, and process image in plain language
- explain the difference between PREOP, SAFEOP, and OP at a practical level
- describe what a cyclic exchange does every cycle
- interpret working counter mismatches as a runtime symptom
- understand why faults may appear first at the domain level and later at the slave level
- explain why multiple domains exist and when they matter
- understand what distributed clocks are for without needing them in the first lessons
- see why message-passing, supervision, and interactive inspection are useful for this domain

## Curriculum Shape

The material should be structured as a ladder, not a catalog. Each step should feel like the natural continuation of the previous one.

### Phase 1: Mental Model

Purpose:
- build intuition for EtherCAT without implementation noise

Status:
- implemented in [01_ethercat_introduction.livemd](./01_ethercat_introduction.livemd)

Target concepts:
- master
- slave
- process data
- cyclic exchange
- network state progression

Desired reader feeling:
- “I know what is happening on the wire at a high level.”

### Phase 2: First Interactive Contact

Purpose:
- let the reader use the simulator to make EtherCAT behavior tangible

Status:
- currently merged into [01_ethercat_introduction.livemd](./01_ethercat_introduction.livemd)

Target concepts:
- fixed ring
- process image
- one output influencing one input
- observable state changes

Desired reader feeling:
- “I can touch this system and understand the effect.”

### Phase 3: Runtime States and Health

Purpose:
- explain state progression and what “healthy” means during operation

Target concepts:
- discovery
- PREOP readiness
- activation to OP
- cycle validity
- working counter expectations

Desired reader feeling:
- “I understand when the system is ready and how it tells me it is not.”

### Phase 4: Faults and Recovery

Purpose:
- make failure modes part of the learning path rather than a later surprise

Target concepts:
- dropped replies
- WKC mismatch
- disconnect
- SAFEOP retreat
- AL error latch
- recovery flow

Desired reader feeling:
- “I can recognize the shape of faults and reason about recovery.”

### Phase 5: Scaling the Model

Purpose:
- expand from the simplest ring to more realistic system structure

Target concepts:
- multiple domains
- differing cycle cadences
- partitioned process data
- observability across resources

Desired reader feeling:
- “I understand why real systems are organized this way.”

### Phase 6: Why Elixir

Purpose:
- connect the protocol model to language/runtime strengths without making the entire course about Elixir

Target concepts:
- processes
- supervision
- message passing
- structured logging
- interactive introspection
- Livebook as a teaching and diagnostics surface

Desired reader feeling:
- “Now I see why this is a good environment for this class of problem.”

## Proposed Sequence

This is the target sequence for future material. It is a plan, not a commitment to exact notebook names.

1. EtherCAT in One Page
   Goal: define the protocol’s purpose and the minimum vocabulary.
   Constraint: no code-first presentation.

2. Simulator Quickstart
   Goal: show that a complete EtherCAT session can be explored without hardware.
   Constraint: minimal configuration, instant visible feedback.

3. Simple Process Data
   Goal: explain the process image through one input/output path.
   Constraint: keep the topology tiny and the signal names intuitive.

4. State Progression
   Goal: walk from startup to operational state and explain each transition.
   Constraint: no advanced detours into DC or mailbox behavior.

5. Cycles, WKC, and Health
   Goal: tie the abstract idea of cyclic exchange to concrete validity checks.
   Constraint: make the meaning of WKC observable rather than theoretical.

6. Fault Injection and Recovery
   Goal: use simulator faults to build intuition for runtime degradation and recovery.
   Constraint: introduce one fault family at a time.

7. Subscriptions and Observability
   Goal: show how change streams and live views make a cyclic system understandable.
   Constraint: keep the focus on observing EtherCAT, not on framework mechanics.

8. Multidomain
   Goal: explain partitioning, cadence, and operational tradeoffs.
   Constraint: justify complexity before presenting it.

9. Distributed Clocks
   Goal: explain timing alignment only after the reader already values cycle behavior.
   Constraint: treat DC as advanced optimization and determinism work, not as day-one setup.

10. Why Elixir for EtherCAT
    Goal: explain the implementation fit after the problem has been internalized.
    Constraint: connect language features directly to the pain points already demonstrated.

## Per-Lesson Design Template

Every future lesson should be built with the same internal structure so the experience feels consistent:

1. Question
   Start with the one question the lesson answers.
2. Concept
   Explain the smallest useful theory needed.
3. Experiment
   Let the reader trigger or observe one concrete behavior.
4. Interpretation
   Explain what changed and why it matters.
5. Limits
   State what the lesson intentionally leaves out.
6. Forward link
   Point to the next concept the reader is now ready for.

This structure keeps the material from becoming either a dry protocol document or a disconnected demo collection.

## Simulator Strategy

The simulator should not be treated as a fake convenience layer. It should be presented as the default educational environment.

Requirements for simulator-based teaching:

- use a stable, named, minimal ring for the early material
- ensure the first exercises work without hardware assumptions
- make signal wiring obvious enough that readers can predict outcomes
- use fault injection intentionally as a teaching tool

The simulator should let the reader experience:

- a healthy cycle
- a process image update
- a WKC mismatch
- a disconnect window
- a recovery path
- the effect of changing cycle organization

## Concept Ordering Rules

Certain ideas should be delayed until the reader has enough context:

- DC should come after the reader understands cycles and basic timing concerns.
- Multidomain should come after the reader understands a single domain well.
- Mailbox-level detail should remain out of the main intro path unless it is needed for a specific later advanced topic.
- Elixir-specific architectural discussion should come after observability and recovery pain points are already visible.

## Tone and Style

The material should read like engineering guidance, not marketing copy and not protocol archaeology.

Desired style:

- plain language
- rigorous but not academic
- interactive and visual where possible
- concrete before abstract
- careful with jargon
- explicit about cause and effect

Avoid:

- long historical digressions
- vendor-specific detours in the intro path
- “click here, now click here” without explaining why
- implementation details that overshadow protocol understanding

## Success Criteria

The intro is successful if a new reader can finish the early path and say:

- “I understand what EtherCAT is doing.”
- “I can explain what OP means and why WKC matters.”
- “I can look at a fault and tell whether it looks like transport, domain, or slave trouble.”
- “I did not need hardware to start learning.”
- “Now I understand why an interactive Elixir environment is useful here.”

It is unsuccessful if readers leave knowing the names of widgets and helpers but still cannot explain the operational model of EtherCAT.

## Build Order

Recommended implementation order for the future material:

1. Write the conceptual outline for the first three lessons before creating any new notebooks.
2. Design the simulator ring and naming scheme that those first lessons will reuse.
3. Define the smallest set of observables needed in the UI for early lessons.
4. Draft the fault-and-recovery narrative before adding advanced topics.
5. Add multidomain and DC only after the basic path feels stable and coherent.
6. Write the “Why Elixir” material last, using concrete lessons already established earlier.

## Repository Intent

Until the new path is ready, this folder should remain plan-oriented rather than shipping half-finished teaching material. The next concrete examples should only be added once they fit this sequence and teaching philosophy.
