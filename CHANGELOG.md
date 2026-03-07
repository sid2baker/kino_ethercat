# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-03-07

### Added

- **EtherCAT Setup SmartCell** — scans the bus, discovers slaves, assigns names and
  drivers, configures domain/cycle time, and generates `EtherCAT.start/1` code
- **EtherCAT Visualizer SmartCell** — drag-to-sort list of running slaves that generates
  `KinoEtherCAT.render/2` calls; supports per-slave column count, trash to remove,
  and refresh to reload from live bus
- **Master phase badge** on Setup SmartCell — polls `EtherCAT.phase/0` every 500 ms and
  shows a color-coded pill (idle/scanning/configuring/pre-op ready/operational/degraded)
- `KinoEtherCAT.led/2,3` — read-only LED indicator for 1-bit input signals
- `KinoEtherCAT.switch/2,3` — toggle switch for 1-bit output signals
- `KinoEtherCAT.value/2,3` — live value display for multi-bit input signals
- `KinoEtherCAT.render/2` — auto-renders all signals for a slave (LEDs, switches, values)
  with `:columns`, `:layout`, and `:on_error` options
- **Built-in driver registry** — `KinoEtherCAT.Driver` with `all/0` and `lookup/1`;
  auto-detects known slaves by vendor/product ID during bus scan
- **Built-in drivers** for Beckhoff EL terminals:
  - `KinoEtherCAT.Driver.EL1809` — 16-channel digital input
  - `KinoEtherCAT.Driver.EL2809` — 16-channel digital output
  - `KinoEtherCAT.Driver.EL3202` — 2-channel PT100 RTD temperature input
