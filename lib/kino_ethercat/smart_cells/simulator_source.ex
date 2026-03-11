defmodule KinoEtherCAT.SmartCells.SimulatorSource do
  @moduledoc false

  alias KinoEtherCAT.SmartCells.{SimulatorConfig, Source}

  @default_simulator_ip {127, 0, 0, 2}

  @spec render(map()) :: String.t()
  def render(attrs) when is_map(attrs) do
    config = normalize(attrs)

    config
    |> source()
    |> Source.format()
  end

  defp source(config) do
    Source.multiline([
      "alias EtherCAT.Simulator\n",
      "alias EtherCAT.Simulator.Slave\n\n",
      "simulator_ip = ",
      ip_literal(config.simulator_ip),
      "\n\n",
      "_ = Simulator.stop()\n\n",
      "devices = ",
      devices_literal(config.selected),
      "\n\n",
      "{:ok, _supervisor} = Simulator.start(devices: devices, udp: [ip: simulator_ip, port: 0])\n\n",
      "KinoEtherCAT.simulator()\n"
    ])
  end

  defp normalize(attrs) do
    %{simulator_ip: simulator_ip, selected: selected} = SimulatorConfig.normalize(attrs)

    %{
      simulator_ip: parse_ip(simulator_ip, @default_simulator_ip),
      selected: SimulatorConfig.selected_entries(selected)
    }
  end

  defp devices_literal([]), do: "[]"

  defp devices_literal(selected) do
    lines =
      selected
      |> Enum.map_join(",\n", fn entry ->
        "  Slave.from_driver(#{entry.driver}, name: #{Source.atom_literal(entry.default_name)})"
      end)

    "[\n#{lines}\n]"
  end

  defp parse_ip(value, default) when is_binary(value) do
    value = String.trim(value)

    case :inet.parse_address(String.to_charlist(value)) do
      {:ok, ip} -> ip
      _ -> default
    end
  end

  defp parse_ip(_value, default), do: default

  defp ip_literal({a, b, c, d}), do: "{#{a}, #{b}, #{c}, #{d}}"
  defp ip_literal(other), do: inspect(other)
end
