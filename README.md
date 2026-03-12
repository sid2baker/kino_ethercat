# KinoEtherCAT

[Livebook](https://livebook.dev) and [Kino](https://github.com/livebook-dev/kino) tools for [EtherCAT](https://github.com/sid2baker/ethercat).

`kino_ethercat` is built around three use cases:

- discover and configure an EtherCAT bus from Livebook
- inspect and control a running master with focused runtime renders
- teach EtherCAT with a simulator-first workflow and low setup friction

## Quick Start

If you want the shortest path to a first useful result, start with the example notebook:

- [EtherCAT Introduction](./examples/01_ethercat_introduction.livemd)

[![Run in Livebook](https://livebook.dev/badge/v1/blue.svg)](https://livebook.dev/run?url=https%3A%2F%2Fraw.githubusercontent.com%2Fsid2baker%2Fkino_ethercat%2Fmain%2Fexamples%2F01_ethercat_introduction.livemd)

That notebook uses the built-in simulator, walks through Setup and Master, and ends with a simple `outputs.ch1 -> inputs.ch1` interaction.

The broader teaching direction lives in [examples/README.md](./examples/README.md).

## Installation

Add `kino_ethercat` to a Livebook notebook:

```elixir
Mix.install([
  {:kino_ethercat, "~> 0.3.0"}
])
```

For local development against this repo:

```elixir
Mix.install([
  {:kino_ethercat, path: "~/path/to/kino_ethercat"}
])
```

When developing this repo itself against a sibling `../ethercat` checkout, set:

```bash
export KINO_ETHERCAT_USE_LOCAL_ETHERCAT=1
```

## Main Surfaces

### Smart Cells

KinoEtherCAT registers Smart Cells in Livebook under **+ Smart**.

#### EtherCAT Setup

Discovers the current bus or simulator and generates a static `EtherCAT.start/1` cell.

- auto-scans when added
- supports raw socket or UDP transport
- lets you name slaves, choose drivers, assign domains, and tune DC
- generates a notebook cell that ends with Master and diagnostics tabs

#### EtherCAT Simulator

Builds a small virtual ring for teaching and testing.

- starts with `coupler -> inputs -> outputs`
- defaults to one loopback path: `outputs.ch1 -> inputs.ch1`
- simple mode keeps the workflow minimal
- `Expert mode` exposes device ordering and connection editing
- simple mode generates `Introduction`, `Simulator`, and `Faults` tabs
- expert mode keeps the simulator workspace focused on `Simulator` and `Faults`

#### EtherCAT Visualizer

Builds a compact signal dashboard from the running bus.

- pick signals with checkboxes grouped by slave
- reorder the selected signal list
- generate focused signal widgets like `led/3`, `switch/3`, and `value/3`

#### EtherCAT Slave Explorer

Combines low-level workflows for a selected slave:

- ESC registers
- CoE SDO
- SII EEPROM

### Runtime Renders

The main runtime API returns renderable EtherCAT resources:

```elixir
KinoEtherCAT.master()
KinoEtherCAT.slave(:io_1)
KinoEtherCAT.domain(:main)
KinoEtherCAT.bus()
KinoEtherCAT.dc()
```

In Livebook, these render as interactive views through `Kino.Render`.

Use them when you want a resource-oriented runtime surface instead of a generated Smart Cell workflow.

### Diagnostics And Simulator Panels

```elixir
KinoEtherCAT.diagnostics()
KinoEtherCAT.introduction()
KinoEtherCAT.simulator()
KinoEtherCAT.simulator_faults()
```

- `diagnostics/0` is the broad Task Manager style overview
- `introduction/0` is the reduced teaching surface
- `simulator/0` is the simulator topology and status view
- `simulator_faults/0` is the fault injection console

## Widgets

Signal-level and slave-panel widgets live under `KinoEtherCAT.Widgets`.

### Signal Widgets

```elixir
KinoEtherCAT.Widgets.led(:inputs, :ch1, label: "Input 1")
KinoEtherCAT.Widgets.switch(:outputs, :ch1, label: "Output 1")
KinoEtherCAT.Widgets.value(:analog, :temperature, label: "Temperature")
```

- `led/3` is a read-only 1-bit input indicator
- `switch/3` writes a 1-bit output
- `value/3` displays multi-bit values

### Slave Panels

```elixir
KinoEtherCAT.Widgets.panel(:inputs)
KinoEtherCAT.Widgets.dashboard([:left_io, :right_io], columns: 2)
```

Use these when you want a compact operator-facing view without the full runtime panels.

## Built-in Drivers

KinoEtherCAT ships built-in drivers for a small Beckhoff-focused teaching and bring-up set:

| Module | Device | Description |
|---|---|---|
| `KinoEtherCAT.Driver.EK1100` | EK1100 | EtherCAT coupler |
| `KinoEtherCAT.Driver.EL1809` | EL1809 | 16-channel digital input |
| `KinoEtherCAT.Driver.EL2809` | EL2809 | 16-channel digital output |
| `KinoEtherCAT.Driver.EL3202` | EL3202 | 2-channel PT100 RTD input |

Driver lookup:

```elixir
KinoEtherCAT.Driver.all()
KinoEtherCAT.Driver.lookup(%{vendor_id: 2, product_code: 0x07113052})
```

Drivers that should work with the simulator also need a companion `MyDriver.Simulator` module implementing `EtherCAT.Simulator.DriverAdapter`.

## Custom Drivers

At minimum, a custom driver needs to implement `EtherCAT.Slave.Driver` and provide identity, signal layout, and signal encoding/decoding:

```elixir
defmodule MyApp.MyDriver do
  @behaviour EtherCAT.Slave.Driver

  @impl true
  def identity do
    %{vendor_id: 0x0000_0002, product_code: 0x1234_5678}
  end

  @impl true
  def signal_model(_config), do: [ch1: 0x1A00]

  @impl true
  def encode_signal(_signal, _config, _value), do: <<>>

  @impl true
  def decode_signal(_signal, _config, <<_::7, bit::1>>), do: bit
  def decode_signal(_signal, _config, _raw), do: 0
end
```

## License

Apache 2.0. See [LICENSE](LICENSE).
