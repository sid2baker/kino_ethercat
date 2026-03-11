defmodule KinoEtherCAT.SmartCells.Simulator do
  use Kino.JS, assets_path: "lib/assets/simulator_cell/build"
  use Kino.JS.Live
  use Kino.SmartCell, name: "EtherCAT Simulator"

  alias KinoEtherCAT.SmartCells.{SimulatorConfig, SimulatorSource}

  @impl true
  def init(attrs, ctx) do
    %{simulator_ip: simulator_ip, selected: selected} = SimulatorConfig.normalize(attrs)

    {:ok,
     assign(ctx,
       simulator_ip: simulator_ip,
       selected: selected,
       next_id: next_id(selected)
     )}
  end

  @impl true
  def handle_connect(ctx) do
    {:ok, payload(ctx.assigns), ctx}
  end

  @impl true
  def handle_event("update", params, ctx) do
    simulator_ip =
      params
      |> Map.get("simulator_ip", ctx.assigns.simulator_ip)
      |> SimulatorConfig.normalize_simulator_ip()

    ctx = assign(ctx, simulator_ip: simulator_ip)
    broadcast_event(ctx, "snapshot", payload(ctx.assigns))
    {:noreply, ctx}
  end

  def handle_event("add_device", %{"driver" => driver}, ctx) do
    if SimulatorConfig.valid_driver?(driver) do
      selected =
        ctx.assigns.selected ++
          [%{"id" => Integer.to_string(ctx.assigns.next_id), "driver" => driver}]

      ctx =
        assign(ctx,
          selected: selected,
          next_id: ctx.assigns.next_id + 1
        )

      broadcast_event(ctx, "snapshot", payload(ctx.assigns))
      {:noreply, ctx}
    else
      {:noreply, ctx}
    end
  end

  def handle_event("reorder", %{"ids" => ids}, ctx) do
    selected = reorder_selected(ctx.assigns.selected, ids)
    ctx = assign(ctx, selected: selected)
    broadcast_event(ctx, "snapshot", payload(ctx.assigns))
    {:noreply, ctx}
  end

  def handle_event("remove", %{"id" => id}, ctx) do
    selected = Enum.reject(ctx.assigns.selected, &(Map.get(&1, "id") == id))
    ctx = assign(ctx, selected: selected)
    broadcast_event(ctx, "snapshot", payload(ctx.assigns))
    {:noreply, ctx}
  end

  @impl true
  def to_attrs(ctx) do
    %{
      "simulator_ip" => ctx.assigns.simulator_ip,
      "selected" => ctx.assigns.selected
    }
  end

  @impl true
  def to_source(attrs) do
    SimulatorSource.render(attrs)
  end

  defp payload(assigns) do
    %{
      title: "EtherCAT Simulator",
      description:
        "Build an ordered simulator ring, start EtherCAT.Simulator over UDP, and render the simulator control panel.",
      simulator_ip: assigns.simulator_ip,
      available_drivers: SimulatorConfig.available_drivers(),
      selected: SimulatorConfig.selected_entries(assigns.selected)
    }
  end

  defp reorder_selected(selected, ids) do
    by_id = Map.new(selected, &{Map.get(&1, "id"), &1})
    ordered = Enum.flat_map(ids, fn id -> Map.get(by_id, id, []) |> List.wrap() end)
    id_set = MapSet.new(ids)
    remaining = Enum.reject(selected, &MapSet.member?(id_set, Map.get(&1, "id")))
    ordered ++ remaining
  end

  defp next_id(selected) do
    selected
    |> Enum.map(&Map.get(&1, "id"))
    |> Enum.map(&Integer.parse(to_string(&1)))
    |> Enum.reduce(1, fn
      {value, ""}, acc -> max(acc, value + 1)
      _, acc -> acc
    end)
  end
end
