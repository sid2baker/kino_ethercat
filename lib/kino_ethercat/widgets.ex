defmodule KinoEtherCAT.Widgets do
  @moduledoc """
  Signal- and slave-oriented Livebook widgets.

  The preferred runtime surface is the renderable resource API in
  `KinoEtherCAT`, but these widgets remain useful for focused operator
  dashboards and narrow hardware bring-up notebooks.
  """

  alias KinoEtherCAT.Widgets.{LED, SlavePanel, Switch, Value}

  @spec led(atom(), atom(), keyword()) :: Kino.JS.Live.t()
  def led(slave, signal, opts \\ []), do: LED.new(slave, signal, opts)

  @spec switch(atom(), atom(), keyword()) :: Kino.JS.Live.t()
  def switch(slave, signal, opts \\ []), do: Switch.new(slave, signal, opts)

  @spec value(atom(), atom(), keyword()) :: Kino.JS.Live.t()
  def value(slave, signal, opts \\ []), do: Value.new(slave, signal, opts)

  @spec panel(atom(), keyword()) :: Kino.JS.Live.t()
  def panel(slave_name, opts \\ []), do: SlavePanel.new(slave_name, opts)

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

  defp panel_columns(0), do: 1
  defp panel_columns(n), do: min(n, 4)
end
