# KinoEtherCAT

Livebook [Kino](https://github.com/livebook-dev/kino) widgets for EtherCAT bus signals.

## Widgets

- `KinoEtherCAT.led/2,3` — read-only LED indicator driven by an input signal
- `KinoEtherCAT.switch/2,3` — toggle switch that writes an output signal

## Usage

Install the local package in Livebook:

```elixir
Mix.install([
  {:kino_ethercat, path: "~/path/to/kino_ethercat"}
])
```

Then use widgets in any cell:

```elixir
KinoEtherCAT.led(:sensor, :ch1)
KinoEtherCAT.led(:sensor, :ch2, color: "red", label: "Fault")

KinoEtherCAT.switch(:valve, :ch1)
KinoEtherCAT.switch(:valve, :ch1, label: "Pump EN", initial: 0)
```

## Development

After editing files under `assets/packs/`, rebuild:

```sh
cd assets && npm run build
```

For live rebuilds during development:

```sh
cd assets && npm run dev
```

Then restart the notebook runtime and re-evaluate (`00` + `Cmd+Shift+Enter`).
