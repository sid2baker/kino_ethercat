defmodule KinoEtherCAT.SmartCells.Visualizer do
  use Kino.JS, assets_path: "lib/assets/visualizer_cell/build"
  use Kino.JS.Live
  use Kino.SmartCell, name: "EtherCAT Visualizer"

  alias KinoEtherCAT.SmartCells.Source

  @impl true
  def init(attrs, ctx) do
    selected = attrs["selected"] || []
    columns = attrs["columns"]
    {status, selected} = if selected == [], do: fetch_slaves(), else: {:ok, selected}

    {:ok, assign(ctx, selected: selected, status: status, columns: columns)}
  end

  @impl true
  def handle_connect(ctx) do
    {:ok,
     %{
       selected: ctx.assigns.selected,
       columns: ctx.assigns.columns,
       status: to_string(ctx.assigns.status)
     }, ctx}
  end

  @impl true
  def handle_event("refresh", _params, ctx) do
    {status, selected} = fetch_slaves()
    payload = %{selected: selected, columns: ctx.assigns.columns, status: to_string(status)}
    broadcast_event(ctx, "refreshed", payload)
    {:noreply, assign(ctx, selected: selected, status: status)}
  end

  def handle_event("reorder", %{"names" => names}, ctx) do
    by_name = Map.new(ctx.assigns.selected, &{&1["name"], &1})
    selected = Enum.flat_map(names, fn name -> Map.get(by_name, name, []) |> List.wrap() end)
    {:noreply, assign(ctx, selected: selected)}
  end

  def handle_event("remove", %{"name" => name}, ctx) do
    selected = Enum.reject(ctx.assigns.selected, &(&1["name"] == name))
    {:noreply, assign(ctx, selected: selected)}
  end

  def handle_event("update_columns", %{"columns" => columns}, ctx) do
    {:noreply, assign(ctx, columns: columns)}
  end

  @impl true
  def to_attrs(ctx) do
    %{"selected" => ctx.assigns.selected, "columns" => ctx.assigns.columns}
  end

  @impl true
  def to_source(%{"selected" => selected} = attrs) do
    slaves =
      selected
      |> Enum.map(&String.trim(&1["name"]))
      |> Enum.reject(&(&1 == ""))

    case slaves do
      [] ->
        ""

      _ ->
        slave_literals =
          slaves
          |> Enum.map_join(", ", &Source.atom_literal/1)

        columns =
          case attrs["columns"] do
            value when is_integer(value) and value > 0 -> ", columns: #{value}"
            _ -> ""
          end

        Source.multiline([
          "KinoEtherCAT.Widgets.dashboard([#{slave_literals}]#{columns}) |> Kino.render()",
          "\n\nKino.nothing()"
        ])
    end
  end

  defp fetch_slaves do
    slaves = EtherCAT.slaves()
    entries = Enum.map(slaves, &%{"name" => to_string(&1.name)})
    {:ok, entries}
  rescue
    _ -> {:not_running, []}
  end
end
