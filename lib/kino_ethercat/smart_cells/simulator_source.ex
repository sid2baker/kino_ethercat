defmodule KinoEtherCAT.SmartCells.SimulatorSource do
  @moduledoc false

  alias KinoEtherCAT.SmartCells.{SimulatorConfig, Source}

  @default_simulator_ip {127, 0, 0, 2}

  @spec render(map()) :: String.t()
  def render(attrs) when is_map(attrs) do
    config = normalize(attrs)
    expert_mode = expert_mode?(attrs)

    config
    |> source(expert_mode)
    |> Source.format()
  end

  defp source(config, expert_mode) do
    Source.multiline([
      "alias EtherCAT.Simulator\n",
      "alias EtherCAT.Simulator.Slave\n\n",
      "simulator_ip = ",
      ip_literal(@default_simulator_ip),
      "\n\n",
      "_ = Simulator.stop()\n\n",
      "devices = ",
      devices_literal(config.selected),
      "\n\n",
      "{:ok, _supervisor} = Simulator.start(devices: devices, udp: [ip: simulator_ip, port: #{SimulatorConfig.default_port()}])\n\n",
      connection_literals(config.connections),
      if(config.connections == [], do: "", else: "\n"),
      "Kino.Layout.tabs(\n",
      tabs_literal(expert_mode),
      ")\n"
    ])
  end

  defp normalize(attrs) do
    %{selected: selected, connections: connections} = SimulatorConfig.normalize(attrs)

    %{
      selected: SimulatorConfig.selected_entries(selected),
      connections: SimulatorConfig.connection_entries(selected, connections)
    }
  end

  defp devices_literal([]), do: "[]"

  defp devices_literal(selected) do
    lines =
      selected
      |> Enum.map_join(",\n", fn entry ->
        "  Slave.from_driver(#{entry.driver}, name: #{Source.atom_literal(entry.name)})"
      end)

    "[\n#{lines}\n]"
  end

  defp connection_literals([]), do: ""

  defp connection_literals(connections) do
    connections
    |> Enum.map_join("\n", fn connection ->
      ":ok = Slave.connect({#{Source.atom_literal(connection.source_name)}, #{Source.atom_literal(connection.source_signal)}}, {#{Source.atom_literal(connection.target_name)}, #{Source.atom_literal(connection.target_signal)}})"
    end)
    |> Kernel.<>("\n")
  end

  defp tabs_literal(true) do
    "  Simulator: KinoEtherCAT.simulator(),\n  Faults: KinoEtherCAT.simulator_faults()\n"
  end

  defp tabs_literal(false) do
    "  Introduction: KinoEtherCAT.introduction(),\n  Simulator: KinoEtherCAT.simulator(),\n  Faults: KinoEtherCAT.simulator_faults()\n"
  end

  defp expert_mode?(attrs) when is_map(attrs),
    do: Map.get(attrs, "expert_mode", false) in [true, "true", 1, "1"]

  defp ip_literal({a, b, c, d}), do: "{#{a}, #{b}, #{c}, #{d}}"
end
