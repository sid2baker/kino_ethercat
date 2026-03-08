# KinoEtherCAT

[Livebook](https://livebook.dev) and [Kino](https://github.com/livebook-dev/kino) tools for [EtherCAT](https://github.com/sid2baker/ethercat) discovery, runtime inspection, diagnostics, and hardware bring-up.

## Installation

Add to your Livebook notebook:

```elixir
Mix.install([
  {:kino_ethercat, "~> 0.2"}
])
```

Or during development from a local path:

```elixir
Mix.install([
  {:kino_ethercat, path: "~/path/to/kino_ethercat"}
])
```

---

## Smart Cells

KinoEtherCAT registers multiple Smart Cells in Livebook (available via **+ Smart** in the cell menu).

### EtherCAT Setup

Scans the bus, discovers connected slaves, lets you assign names and drivers, and generates a static `EtherCAT.start/1` call that returns the running master pid.

- Set the network interface and click **Scan Bus**
- Assign a human-readable name to each slave
- Pick a built-in driver from the dropdown (auto-detected by vendor/product ID) or type a custom module name
- Configure multiple domains and assign each slave to a domain
- Tune grouped DC settings without leaving the cell
- The master phase badge (top-right) shows live EtherCAT state

### EtherCAT Visualizer

Picks running slaves and generates `KinoEtherCAT.Widgets.dashboard/2` calls for focused operator panels.

- Click **Refresh** to load the current slave list
- Drag rows to reorder render output
- Click the trash icon to exclude a slave
- Set **columns** to control dashboard layout

### EtherCAT SDO Explorer

Generates repeatable CoE upload and download code against the selected configured slave.

### EtherCAT Register Explorer

Generates ESC register reads and writes, with presets for common AL, DL, watchdog, and sync manager diagnostics.

### EtherCAT SII Explorer

Generates EEPROM and ESC reload calls for identity, mailbox, sync manager, PDO, and raw word access.

## Programmatic API

### Runtime Resources

The preferred runtime API returns renderable EtherCAT structs:

```elixir
KinoEtherCAT.master()
KinoEtherCAT.slave(:io_1)
KinoEtherCAT.domain(:main)
KinoEtherCAT.dc()
KinoEtherCAT.bus()
```

In Livebook these render as interactive resource views via `Kino.Render`.

### Diagnostics

```elixir
KinoEtherCAT.diagnostics()
KinoEtherCAT.Diagnostics.panel()
```

### Widgets

Signal-level and slave-panel widgets live under `KinoEtherCAT.Widgets`.

#### LED

Read-only indicator driven by a 1-bit EtherCAT input signal. Lights up when the value is `1`.

```elixir
KinoEtherCAT.Widgets.led(:my_slave, :ch1)
KinoEtherCAT.Widgets.led(:my_slave, :ch2, label: "Fault", color: "red")
```

**Options:** `:label` (default: signal name), `:color` — `"green"` | `"red"` | `"yellow"` | `"blue"` (default: `"green"`)

#### Switch

Toggle switch that writes a 1-bit EtherCAT output signal.

```elixir
KinoEtherCAT.Widgets.switch(:my_slave, :ch1)
KinoEtherCAT.Widgets.switch(:my_slave, :ch1, label: "Pump EN", initial: 0)
```

**Options:** `:label` (default: signal name), `:initial` — `0` or `1` (default: `0`)

#### Value

Live display for multi-bit input signals (e.g. temperature readings, analog inputs).

```elixir
KinoEtherCAT.Widgets.value(:rtd, :channel1)
KinoEtherCAT.Widgets.value(:rtd, :channel1, label: "PT100 CH1")
```

**Options:** `:label` (default: signal name)

#### Slave Panels

Aggregate one or more configured slaves into focused dashboard panels.

```elixir
KinoEtherCAT.Widgets.panel(:my_slave)
KinoEtherCAT.Widgets.dashboard([:left_io, :right_io], columns: 2)
```

**Options:**
- `:columns` — max panels per row on `dashboard/2`
- `:batch_ms` — signal update batching interval on `panel/2`
- `:show_identity?` — whether `panel/2` shows slave identity details
- `:show_domains?` — whether `panel/2` shows domain health badges

---

## Built-in Drivers

KinoEtherCAT ships drivers for common Beckhoff EL terminals. These are automatically selected in the **EtherCAT Setup** SmartCell when a matching slave is detected.

| Module | Device | Description |
|---|---|---|
| `KinoEtherCAT.Driver.EL1809` | EL1809 | 16-channel digital input, 24 V DC |
| `KinoEtherCAT.Driver.EL2809` | EL2809 | 16-channel digital output, 24 V DC |
| `KinoEtherCAT.Driver.EL3202` | EL3202 | 2-channel PT100 RTD temperature input |

### Driver Registry

Look up or enumerate registered drivers:

```elixir
# All registered drivers (for UI or tooling)
KinoEtherCAT.Driver.all()
#=> [%{module: KinoEtherCAT.Driver.EL1809, name: "EL1809",
#      vendor_id: 2, product_code: 0x07113052}, ...]

# Resolve a slave identity to its driver module
KinoEtherCAT.Driver.lookup(%{vendor_id: 2, product_code: 0x07113052})
#=> {:ok, %{module: KinoEtherCAT.Driver.EL1809, name: "EL1809", ...}}

KinoEtherCAT.Driver.lookup(%{vendor_id: 2, product_code: 0x044C2C52})
#=> :error
```

### Custom Drivers

Implement `EtherCAT.Slave.Driver` and pass the module to `EtherCAT.start/1`:

```elixir
defmodule MyApp.MyDriver do
  @behaviour EtherCAT.Slave.Driver

  @impl true
  def process_data_model(_config), do: [ch1: 0x1A00]

  @impl true
  def encode_signal(_pdo, _config, _value), do: <<>>

  @impl true
  def decode_signal(_ch, _config, <<_::7, bit::1>>), do: bit
  def decode_signal(_pdo, _config, _), do: 0
end
```

---

## License

Apache 2.0 — see [LICENSE](LICENSE).
