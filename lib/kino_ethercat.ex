defmodule KinoEtherCAT do
  @moduledoc """
  Livebook Kino widgets for EtherCAT bus discovery, control, and diagnostics.
  """

  alias KinoEtherCAT.{Diagnostics, LED, SDOExplorer, SlavePanel, Switch}

  @doc """
  Render a read-only LED indicator driven by an EtherCAT input signal.

  Subscribes to `{slave, signal}` and lights up when the value is `1`.

  ## Options

    * `:label` — text label shown next to the LED (default: `"signal"`)
    * `:color` — LED color when on: `"green"` | `"red"` | `"yellow"` | `"blue"` (default: `"green"`)
  """
  @spec led(atom(), atom(), keyword()) :: Kino.JS.Live.t()
  def led(slave, signal, opts \\ []), do: LED.new(slave, signal, opts)

  @doc """
  Render a toggle switch that writes an EtherCAT output signal.

  Clicking the switch calls `EtherCAT.write_output/3` with `0` or `1`.

  ## Options

    * `:label` — text label shown next to the switch (default: `"signal"`)
    * `:initial` — initial value, `0` or `1` (default: `0`)
  """
  @spec switch(atom(), atom(), keyword()) :: Kino.JS.Live.t()
  def switch(slave, signal, opts \\ []), do: Switch.new(slave, signal, opts)

  @doc """
  Render a live aggregated panel for a single slave.

  The panel shows live input values, bit outputs, slave metadata, and domain
  health in a single widget. Unlike the older per-signal grid, this keeps
  updates batched and lets the widget recover if the master is restarted.

  ## Options

    * `:title` — panel title override
    * `:batch_ms` — signal update batching interval in milliseconds. Default: `100`
    * `:show_identity?` — whether to show slave identity details. Default: `true`
    * `:show_domains?` — whether to show domain health badges. Default: `true`
  """
  @spec render(atom(), keyword()) :: Kino.JS.Live.t()
  def render(slave_name, opts \\ []), do: panel(slave_name, opts)

  @doc """
  Render a live aggregated panel for a single EtherCAT slave.
  """
  @spec panel(atom(), keyword()) :: Kino.JS.Live.t()
  def panel(slave_name, opts \\ []), do: SlavePanel.new(slave_name, opts)

  @doc """
  Render multiple slave panels in a grid.

  ## Options

    * `:columns` — max panels per row. Default: auto, up to 4

  Any other options are forwarded to `panel/2`.
  """
  @spec dashboard([atom()], keyword()) :: Kino.Layout.t() | Kino.JS.Live.t() | Kino.nothing()
  def dashboard(slaves, opts \\ []) when is_list(slaves) do
    columns = Keyword.get(opts, :columns, nil)
    panel_opts = Keyword.drop(opts, [:columns])

    widgets = Enum.map(slaves, &panel(&1, panel_opts))

    case widgets do
      [] -> Kino.nothing()
      [widget] -> widget
      _ -> Kino.Layout.grid(widgets, columns: columns || panel_columns(length(widgets)))
    end
  end

  @doc """
  Render a live diagnostic dashboard for the EtherCAT master.

  Polls every 500 ms and displays:
  - Master phase
  - Per-slave ESM state and AL error codes
  - Domain cycle statistics (cycle count, miss count, working counter)
  - Distributed Clocks lock status (when configured)
  """
  @spec diagnostics() :: Kino.JS.Live.t()
  def diagnostics, do: Diagnostics.new()

  @doc """
  Render a mailbox / SDO explorer for CoE-capable slaves.

  The explorer discovers running CoE slaves, lets you upload or download a
  mailbox object entry, and keeps a short operation history in the widget.

  ## Options

    * `:slave` — preferred default slave name
    * `:index` — default object index. Default: `0x1018`
    * `:subindex` — default object subindex. Default: `0`
    * `:write_data` — default hex payload for downloads
  """
  @spec sdo_explorer(keyword()) :: Kino.JS.Live.t()
  def sdo_explorer(opts \\ []), do: SDOExplorer.new(opts)

  defp panel_columns(0), do: 1
  defp panel_columns(n), do: min(n, 4)
end
