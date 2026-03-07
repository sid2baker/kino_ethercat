# KinoEtherCAT

[Livebook](https://livebook.dev) [Kino](https://github.com/livebook-dev/kino) widgets for [EtherCAT](https://github.com/sid2baker/ethercat) bus signals.

## Installation

Add to your Livebook notebook:

```elixir
Mix.install([
  {:kino_ethercat, "~> 0.1"}
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

KinoEtherCAT registers two Smart Cells in Livebook (available via **+ Smart** in the cell menu).

### EtherCAT Setup

Scans the bus, discovers connected slaves, lets you assign names and drivers, and generates the `EtherCAT.start/1` call.

- Set the network interface and click **Scan Bus**
- Assign a human-readable name to each slave
- Pick a built-in driver from the dropdown (auto-detected by vendor/product ID) or type a custom module name
- Configure the domain ID and cycle time
- The master phase badge (top-right) shows live EtherCAT state

### EtherCAT Visualizer

Picks running slaves and generates `KinoEtherCAT.render/2` calls — one output cell per slave.

- Click **Refresh** to load the current slave list
- Drag rows to reorder render output
- Click the trash icon to exclude a slave
- Set **per row** to control how many signals appear per grid row (blank = auto)

---

## Programmatic API

### LED

Read-only indicator driven by a 1-bit EtherCAT input signal. Lights up when the value is `1`.

```elixir
KinoEtherCAT.led(:my_slave, :ch1)
KinoEtherCAT.led(:my_slave, :ch2, label: "Fault", color: "red")
```

**Options:** `:label` (default: signal name), `:color` — `"green"` | `"red"` | `"yellow"` | `"blue"` (default: `"green"`)

### Switch

Toggle switch that writes a 1-bit EtherCAT output signal.

```elixir
KinoEtherCAT.switch(:my_slave, :ch1)
KinoEtherCAT.switch(:my_slave, :ch1, label: "Pump EN", initial: 0)
```

**Options:** `:label` (default: signal name), `:initial` — `0` or `1` (default: `0`)

### Value

Live display for multi-bit input signals (e.g. temperature readings, analog inputs).

```elixir
KinoEtherCAT.value(:rtd, :channel1)
KinoEtherCAT.value(:rtd, :channel1, label: "PT100 CH1")
```

**Options:** `:label` (default: signal name)

### render/2

Auto-renders all signals for a slave. Inspects the slave via `EtherCAT.slave_info/1` and creates:
- LEDs for 1-bit inputs
- Switches for 1-bit outputs
- Value displays for multi-bit inputs

```elixir
KinoEtherCAT.render(:my_slave)
KinoEtherCAT.render(:my_slave, columns: 8)
```

**Options:**
- `:columns` — signals per row (default: auto, up to 8)
- `:layout` — `:columns` (inputs/outputs in separate groups) | `:list` (flat). Default: `:columns`
- `:on_error` — `:placeholder` (markdown cell) | `:raise`. Default: `:placeholder`

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
