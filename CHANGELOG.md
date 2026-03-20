# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.0] - 2026-03-20

### Added

- A new `examples/02_redundant_replug_watch.livemd` notebook for redundant replug and transport-fault observation flows

### Changed

- The library now depends on `ethercat ~> 0.4.0` and aligns the slave capture plus simulator fault tooling with that release line
- The diagnostics surface now gives bus-level transport visibility, link-state event history, and stronger task-manager feedback during runtime troubleshooting
- The setup, simulator, and introduction flow now push more of the EtherCAT bring-up path through the smart cells, with more stable transport defaults and scan control
- The slave explorer and simulator fault tools were reorganized around capture-driven inspection and direct slave or bus fault injection workflows

### Fixed

- Slave explorer field editing and fullscreen widget spacing are more stable during longer Livebook sessions
- Widget log routing and runtime control surfaces are aligned so bus-scoped events stay visible in the relevant panels

## [0.3.3] - 2026-03-12

### Changed

- Generated setup cells now keep the startup code simple by emitting a single `start_opts` block plus direct public `EtherCAT.start/1`, `await_running/1`, and `await_operational/1` calls

### Fixed

- UDP setup cells now surface `:eaddrinuse` directly instead of retrying automatically, so notebook behavior stays explicit and easier to understand
- The introduction notebook now matches the simpler generated setup source

## [0.3.2] - 2026-03-12

### Fixed

- UDP setup cells now retry `EtherCAT.start/1` briefly after discovery so simulator-backed setup avoids transient `:eaddrinuse` bind races
- The introduction notebook now uses the published `kino_ethercat` dependency directly for the current release

## [0.3.1] - 2026-03-12

### Added

- Bus payload throughput telemetry and charts in diagnostics

### Changed

- The visualizer smart cell is now centered on an ordered signal path, with automatic widget selection and bus-order grouping
- The simulator fault panel now leads with quick fault actions and moves the generic builders into advanced sections
- The teaching flow and introduction notebook were polished around the simulator-to-setup-to-master path

### Fixed

- The visualizer smart cell now generates simpler, valid source code from signal selections
- The simulator introduction checklist no longer repeats steps that are already complete inside the simulator workspace

## [0.3.0] - 2026-03-12

### Added

- A simulator-first teaching surface with `KinoEtherCAT.introduction/0` and the `examples/01_ethercat_introduction.livemd` notebook
- `EtherCAT Simulator` and `EtherCAT Visualizer` smart cells oriented around a small loopback teaching workflow
- Dedicated simulator overview and simulator fault-injection panels
- Widget-scoped log routing so EtherCAT logs stay inside the corresponding Livebook renders
- Per-resource runtime controls for master, slaves, domains, bus, and distributed clocks

### Changed

- The setup smart cell now auto-discovers the current bus or simulator when added to a notebook
- Simulator-backed setup defaults to UDP transport, `127.0.0.2:34980`, and a more reliable `frame_timeout_ms: 10`
- The master render is now a reduced session-overview surface instead of duplicating the diagnostics page
- The visualizer smart cell is now signal-centric and generates focused `led/3`, `switch/3`, and `value/3` layouts
- The library is aligned to the `ethercat` `0.3.0` lifecycle model, including master deactivation targets

### Fixed

- Setup discovery now inherits simulator device names and re-scan restarts discovery so simulator edits are picked up
- Domain WKC display now shows actual mismatch values during invalid cycles
- Simulator introduction diagrams now use deterministic Mermaid ids to avoid duplicate DOM id warnings in Livebook
- Generated setup source reports startup failures without crashing the notebook cell

## [0.2.0] - 2026-03-09

### Added

- Renderable runtime resources for `Master`, `Slave`, `Domain`, `Bus`, and `DC`
- A telemetry-driven diagnostics dashboard with time-sliced charts and a scrollable event timeline
- A combined `EtherCAT Slave Explorer` Smart Cell for CoE SDO, ESC register, and SII EEPROM workflows
- Top-level testing notebooks under `examples/testing/` for loopback, DC lock, watchdog recovery, and manual fault tolerance checks

### Changed

- The setup Smart Cell now discovers the live bus, persists a static `EtherCAT.start/1` configuration, and ends with master and diagnostics tabs
- Runtime rendering, diagnostics, widgets, and Smart Cells were reorganized into feature-based namespaces and a denser operator-focused UI
- The library now depends on `ethercat` `~> 0.2.0`

### Removed

- The earlier notebook testing framework in favor of plain Livebook-based test flows
- Legacy flat widget helpers and the legacy per-slave render helper API

### Fixed

- Smart Cell source generation is now formatted before it is written back into notebooks
- Runtime panels, diagnostics, and widgets were aligned with the refactored `ethercat` 0.2 runtime state surfaces

## [0.1.0] - 2026-03-07

### Added

- **EtherCAT Setup SmartCell** — scans the bus, discovers slaves, assigns names and
  drivers, configures domain/cycle time, and generates `EtherCAT.start/1` code
- **EtherCAT Visualizer SmartCell** — drag-to-sort list of running slaves that generates
  dashboard code; supports per-slave column count, trash to remove, and refresh to
  reload from the live bus
- **Master lifecycle badge** on Setup SmartCell — polls the runtime state every 500 ms and
  shows a color-coded pill for the current master lifecycle
- Legacy signal widgets for 1-bit inputs, 1-bit outputs, and multi-bit input values
- A legacy helper to auto-render all signals for a slave with layout options
- **Built-in driver registry** — `KinoEtherCAT.Driver` with `all/0` and `lookup/1`;
  auto-detects known slaves by vendor/product ID during bus scan
- **Built-in drivers** for Beckhoff EL terminals:
  - `KinoEtherCAT.Driver.EL1809` — 16-channel digital input
  - `KinoEtherCAT.Driver.EL2809` — 16-channel digital output
  - `KinoEtherCAT.Driver.EL3202` — 2-channel PT100 RTD temperature input
