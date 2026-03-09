# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-03-09

### Added

- Renderable runtime resources for `Master`, `Slave`, `Domain`, `Bus`, and `DC`
- A telemetry-driven diagnostics dashboard with time-sliced charts and a scrollable event timeline
- A combined `EtherCAT Slave Explorer` Smart Cell for CoE SDO, ESC register, and SII EEPROM workflows
- Top-level testing Livebooks under `livebooks/testing/` for loopback, DC lock, watchdog recovery, and manual fault tolerance checks

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
