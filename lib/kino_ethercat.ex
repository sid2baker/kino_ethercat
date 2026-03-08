defmodule KinoEtherCAT do
  @moduledoc """
  Livebook Kino widgets for EtherCAT bus signals.
  """

  alias KinoEtherCAT.{LED, Switch, Value, Diagnostics}

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
  Auto-render all signals for a slave.

  Calls `EtherCAT.slave_info/1` and renders:
  - 1-bit input signals as LEDs
  - 1-bit output signals as Switches
  - Multi-bit input signals as Value displays

  ## Options

    * `:columns` — max signals per row (default: auto, up to 8)
    * `:layout` — `:columns` (inputs/outputs in separate groups) | `:list` (flat). Default: `:columns`
    * `:on_error` — `:raise` | `:placeholder` (markdown cell). Default: `:placeholder`
  """
  @spec render(atom(), keyword()) :: Kino.JS.Live.t() | Kino.Layout.t() | Kino.Markdown.t()
  def render(slave_name, opts \\ []) do
    layout = Keyword.get(opts, :layout, :columns)
    on_error = Keyword.get(opts, :on_error, :placeholder)
    columns = Keyword.get(opts, :columns, nil)

    case fetch_signals(slave_name) do
      {:ok, signals} -> build_layout(slave_name, signals, layout, columns)
      {:error, reason} -> handle_error(slave_name, reason, on_error)
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

  defp fetch_signals(slave_name) do
    case EtherCAT.slave_info(slave_name) do
      {:ok, info} -> {:ok, info.signals}
      {:error, _} = err -> err
    end
  end

  defp build_layout(slave_name, signals, :columns, columns) do
    {bit1, multi} = Enum.split_with(signals, &(&1.bit_size == 1))

    inputs =
      bit1
      |> Enum.filter(&(&1.direction == :input))
      |> Enum.map(&LED.new(slave_name, &1.name))

    outputs =
      bit1
      |> Enum.filter(&(&1.direction == :output))
      |> Enum.map(&Switch.new(slave_name, &1.name))

    values =
      multi
      |> Enum.filter(&(&1.direction == :input))
      |> Enum.map(&Value.new(slave_name, &1.name))

    sections =
      [inputs, outputs, values]
      |> Enum.reject(&Enum.empty?/1)
      |> Enum.map(&Kino.Layout.grid(&1, columns: columns || grid_columns(length(&1))))

    Kino.Layout.grid(sections, columns: 1)
  end

  defp build_layout(slave_name, signals, :list, columns) do
    widgets =
      signals
      |> Enum.flat_map(fn
        %{direction: :input, bit_size: 1, name: name} -> [LED.new(slave_name, name)]
        %{direction: :output, bit_size: 1, name: name} -> [Switch.new(slave_name, name)]
        %{direction: :input, name: name} -> [Value.new(slave_name, name)]
        _ -> []
      end)

    Kino.Layout.grid(widgets, columns: columns || grid_columns(length(widgets)))
  end

  defp grid_columns(0), do: 1
  defp grid_columns(n), do: min(n, 8)

  defp handle_error(slave_name, reason, :raise),
    do: raise("KinoEtherCAT.render failed for #{slave_name}: #{reason}")

  defp handle_error(slave_name, reason, :placeholder),
    do: Kino.Markdown.new("`KinoEtherCAT` — `#{slave_name}` unavailable: `#{reason}`")
end
