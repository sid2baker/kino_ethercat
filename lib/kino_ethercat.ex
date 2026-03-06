defmodule KinoEtherCAT do
  @moduledoc """
  Livebook Kino widgets for EtherCAT bus signals.
  """

  @doc """
  Render a read-only LED indicator driven by an EtherCAT input signal.

  Subscribes to `{slave, signal}` and lights up when the value is `1`.

  ## Options

    * `:label` — text label shown next to the LED (default: `"slave.signal"`)
    * `:color` — LED color when on: `"green"` | `"red"` | `"yellow"` | `"blue"` (default: `"green"`)
  """
  @spec led(atom(), atom(), keyword()) :: Kino.JS.Live.t()
  def led(slave, signal, opts \\ []), do: KinoEtherCAT.LED.new(slave, signal, opts)

  @doc """
  Render a toggle switch that writes an EtherCAT output signal.

  Clicking the switch calls `EtherCAT.write_output/3` with `0` or `1`.

  ## Options

    * `:label` — text label shown next to the switch (default: `"slave.signal"`)
    * `:initial` — initial value, `0` or `1` (default: `0`)
  """
  @spec switch(atom(), atom(), keyword()) :: Kino.JS.Live.t()
  def switch(slave, signal, opts \\ []), do: KinoEtherCAT.Switch.new(slave, signal, opts)
end
