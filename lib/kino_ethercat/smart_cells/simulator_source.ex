defmodule KinoEtherCAT.SmartCells.SimulatorSource do
  @moduledoc false

  alias KinoEtherCAT.SmartCells.Source

  @default_master_ip {127, 0, 0, 1}
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
      "alias EtherCAT.Domain.Config, as: DomainConfig\n",
      "alias EtherCAT.Simulator\n",
      "alias EtherCAT.Simulator.Slave\n",
      "alias EtherCAT.Slave.Config, as: SlaveConfig\n\n",
      "master_ip = ",
      ip_literal(config.master_ip),
      "\n",
      "simulator_ip = ",
      ip_literal(config.simulator_ip),
      "\n",
      "cycle_time_ms = ",
      Source.integer_literal(config.cycle_time_ms),
      "\n",
      "signal_names = ",
      signal_names_literal(),
      "\n\n",
      "_ = EtherCAT.stop()\n",
      "_ = Simulator.stop()\n\n",
      "devices = [\n",
      "  Slave.from_driver(KinoEtherCAT.Driver.EK1100, name: :coupler),\n",
      "  Slave.from_driver(KinoEtherCAT.Driver.EL1809, name: :inputs),\n",
      "  Slave.from_driver(KinoEtherCAT.Driver.EL2809, name: :outputs)\n",
      "]\n\n",
      "{:ok, _supervisor} = Simulator.start(devices: devices, udp: [ip: simulator_ip, port: 0])\n",
      "{:ok, %{udp: %{port: port}}} = Simulator.info()\n\n",
      "Process.sleep(20)\n\n",
      "Enum.each(signal_names, fn signal ->\n",
      "  :ok = Slave.connect({:outputs, signal}, {:inputs, signal})\n",
      "end)\n\n",
      ":ok =\n",
      "  EtherCAT.start(\n",
      "    transport: :udp,\n",
      "    bind_ip: master_ip,\n",
      "    host: simulator_ip,\n",
      "    port: port,\n",
      "    dc: nil,\n",
      "    scan_stable_ms: 20,\n",
      "    scan_poll_ms: 10,\n",
      "    frame_timeout_ms: 5,\n",
      "    domains: [%DomainConfig{id: :main, cycle_time_us: cycle_time_ms * 1_000}],\n",
      "    slaves: [\n",
      "      %SlaveConfig{\n",
      "        name: :coupler,\n",
      "        driver: KinoEtherCAT.Driver.EK1100,\n",
      "        process_data: :none,\n",
      "        target_state: :op\n",
      "      },\n",
      "      %SlaveConfig{\n",
      "        name: :inputs,\n",
      "        driver: KinoEtherCAT.Driver.EL1809,\n",
      "        process_data: {:all, :main},\n",
      "        target_state: :op\n",
      "      },\n",
      "      %SlaveConfig{\n",
      "        name: :outputs,\n",
      "        driver: KinoEtherCAT.Driver.EL2809,\n",
      "        process_data: {:all, :main},\n",
      "        target_state: :op\n",
      "      }\n",
      "    ]\n",
      "  )\n\n",
      ":ok = EtherCAT.await_operational(2_000)\n\n",
      "Kino.Layout.tabs(\n",
      "  \"Task Manager\": KinoEtherCAT.diagnostics(),\n",
      "  Inputs: KinoEtherCAT.Widgets.panel(:inputs),\n",
      "  Outputs: KinoEtherCAT.Widgets.panel(:outputs)\n",
      ")\n"
    ])
  end

  defp normalize(attrs) do
    %{
      master_ip: parse_ip(Map.get(attrs, "master_ip"), @default_master_ip),
      simulator_ip: parse_ip(Map.get(attrs, "simulator_ip"), @default_simulator_ip),
      cycle_time_ms: positive_integer(Map.get(attrs, "cycle_time_ms"), 10)
    }
  end

  defp parse_ip(value, default) when is_binary(value) do
    value = String.trim(value)

    case :inet.parse_address(String.to_charlist(value)) do
      {:ok, ip} -> ip
      _ -> default
    end
  end

  defp parse_ip(_value, default), do: default

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value

  defp positive_integer(value, default) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> default
    end
  end

  defp positive_integer(_value, default), do: default

  defp ip_literal({a, b, c, d}), do: "{#{a}, #{b}, #{c}, #{d}}"
  defp ip_literal(other), do: inspect(other)

  defp signal_names_literal do
    "[" <>
      Enum.map_join(1..16, ", ", fn channel ->
        Source.atom_literal("ch#{channel}")
      end) <> "]"
  end
end
