defmodule KinoEtherCAT.SmartCells.Simulator do
  use Kino.JS, assets_path: "lib/assets/simulator_cell/build"
  use Kino.JS.Live
  use Kino.SmartCell, name: "EtherCAT Simulator"

  alias KinoEtherCAT.SmartCells.{SimulatorConfig, SimulatorRuntime, SimulatorSource}

  @refresh_interval_ms 1_000

  @impl true
  def init(attrs, ctx) do
    %{selected: selected, connections: connections} = SimulatorConfig.normalize(attrs)
    schedule_refresh()

    {:ok,
     assign(ctx,
       selected: selected,
       connections: connections,
       expert_mode: expert_mode?(attrs),
       next_id: next_id(selected),
       runtime_message: nil
     )}
  end

  @impl true
  def handle_connect(ctx) do
    {:ok, payload(ctx.assigns), ctx}
  end

  @impl true
  def handle_event("add_device", %{"driver" => driver}, ctx) do
    if SimulatorConfig.valid_driver?(driver) do
      selected =
        ctx.assigns.selected ++
          [%{"id" => Integer.to_string(ctx.assigns.next_id), "driver" => driver}]

      ctx =
        assign(ctx,
          selected: selected,
          connections:
            SimulatorConfig.normalize(%{
              "selected" => selected,
              "connections" => ctx.assigns.connections
            }).connections,
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

    connections =
      SimulatorConfig.normalize(%{
        "selected" => selected,
        "connections" => ctx.assigns.connections
      }).connections

    ctx = assign(ctx, selected: selected, connections: connections)
    broadcast_event(ctx, "snapshot", payload(ctx.assigns))
    {:noreply, ctx}
  end

  def handle_event("runtime_action", %{"id" => id}, ctx) do
    ctx = assign(ctx, runtime_message: SimulatorRuntime.perform(id))
    broadcast_event(ctx, "snapshot", payload(ctx.assigns))
    {:noreply, ctx}
  end

  def handle_event("set_expert_mode", %{"enabled" => enabled}, ctx) do
    ctx = assign(ctx, expert_mode: truthy?(enabled))
    broadcast_event(ctx, "snapshot", payload(ctx.assigns))
    {:noreply, ctx}
  end

  def handle_event("rename", %{"id" => id, "name" => name}, ctx) do
    selected =
      Enum.map(ctx.assigns.selected, fn entry ->
        if Map.get(entry, "id") == id do
          Map.put(entry, "name", name)
        else
          entry
        end
      end)

    %{selected: selected, connections: connections} =
      SimulatorConfig.normalize(%{
        "selected" => selected,
        "connections" => ctx.assigns.connections
      })

    ctx = assign(ctx, selected: selected, connections: connections)
    broadcast_event(ctx, "snapshot", payload(ctx.assigns))
    {:noreply, ctx}
  end

  def handle_event("remove", %{"id" => id}, ctx) do
    selected = Enum.reject(ctx.assigns.selected, &(Map.get(&1, "id") == id))

    connections =
      ctx.assigns.connections
      |> Enum.reject(fn connection ->
        Map.get(connection, "source_id") == id or Map.get(connection, "target_id") == id
      end)
      |> then(fn connections ->
        SimulatorConfig.normalize(%{
          "selected" => selected,
          "connections" => connections
        }).connections
      end)

    ctx = assign(ctx, selected: selected, connections: connections)
    broadcast_event(ctx, "snapshot", payload(ctx.assigns))
    {:noreply, ctx}
  end

  def handle_event("reset_defaults", _params, ctx) do
    selected = SimulatorConfig.default_selected()
    connections = SimulatorConfig.default_connections(selected)

    ctx =
      assign(ctx,
        selected: selected,
        connections: connections,
        next_id: next_id(selected),
        runtime_message: info_message("Loopback ring reset.")
      )

    broadcast_event(ctx, "snapshot", payload(ctx.assigns))
    {:noreply, ctx}
  end

  def handle_event("auto_wire_matching", _params, ctx) do
    {connections, stats} = SimulatorConfig.auto_wire_matching(ctx.assigns.selected)

    ctx =
      assign(ctx,
        connections: connections,
        runtime_message: auto_wire_message(stats)
      )

    broadcast_event(ctx, "snapshot", payload(ctx.assigns))
    {:noreply, ctx}
  end

  def handle_event("remove_connection", %{"key" => key}, ctx) do
    connections =
      Enum.reject(ctx.assigns.connections, fn connection ->
        connection_key(connection) == key
      end)

    ctx =
      assign(ctx,
        connections: connections,
        runtime_message: info_message("Connection removed.")
      )

    broadcast_event(ctx, "snapshot", payload(ctx.assigns))
    {:noreply, ctx}
  end

  @impl true
  def handle_info(:refresh_runtime, ctx) do
    schedule_refresh()
    broadcast_event(ctx, "snapshot", payload(ctx.assigns))
    {:noreply, ctx}
  end

  @impl true
  def to_attrs(ctx) do
    %{
      "selected" => ctx.assigns.selected,
      "connections" => ctx.assigns.connections,
      "expert_mode" => ctx.assigns.expert_mode
    }
  end

  @impl true
  def to_source(attrs) do
    SimulatorSource.render(attrs)
  end

  defp payload(assigns) do
    selected = SimulatorConfig.selected_entries(assigns.selected)
    connections = SimulatorConfig.connection_entries(assigns.selected, assigns.connections)

    %{
      title: "EtherCAT Simulator",
      description: description(assigns.expert_mode),
      simulator_host: SimulatorConfig.default_simulator_ip(),
      simulator_port: SimulatorConfig.default_port(),
      available_drivers: SimulatorConfig.available_drivers(),
      expert_mode: assigns.expert_mode,
      selected: selected,
      connections: connections,
      runtime: SimulatorRuntime.payload(selected, connections, assigns.runtime_message)
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

  defp schedule_refresh do
    Process.send_after(self(), :refresh_runtime, @refresh_interval_ms)
  end

  defp auto_wire_message(%{matched: 0}) do
    %{level: "info", text: "No unambiguous output/input matches found."}
  end

  defp auto_wire_message(%{matched: matched}) do
    %{level: "info", text: "Auto-wired #{matched} matching signals."}
  end

  defp info_message(text), do: %{level: "info", text: text}

  defp connection_key(connection) do
    "#{Map.get(connection, "source_id")}.#{Map.get(connection, "source_signal")}->#{Map.get(connection, "target_id")}.#{Map.get(connection, "target_signal")}"
  end

  defp expert_mode?(attrs) when is_map(attrs) do
    attrs
    |> Map.get("expert_mode", false)
    |> truthy?()
  end

  defp truthy?(value) when value in [true, "true", 1, "1"], do: true
  defp truthy?(_value), do: false

  defp description(true) do
    "Build an ordered simulator ring, start EtherCAT.Simulator on 127.0.0.2:34980, and render the advanced simulator tabs."
  end

  defp description(false) do
    "Start a simple EtherCAT simulator workspace with the default loopback ring. Enable Expert mode if you want to change the ring layout or loopback wiring."
  end
end
