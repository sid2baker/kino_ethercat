defmodule KinoEtherCAT.SmartCells.SimulatorRuntimeTest do
  use ExUnit.Case, async: false

  alias EtherCAT.Simulator
  alias EtherCAT.Simulator.Slave
  alias KinoEtherCAT.SmartCells.{SimulatorConfig, SimulatorRuntime}

  setup do
    _ = Simulator.stop()

    devices = [
      Slave.from_driver(KinoEtherCAT.Driver.EK1100, name: :coupler),
      Slave.from_driver(KinoEtherCAT.Driver.EL1809, name: :inputs),
      Slave.from_driver(KinoEtherCAT.Driver.EL2809, name: :outputs)
    ]

    {:ok, _supervisor} =
      Simulator.start(devices: devices, udp: [ip: {127, 0, 0, 2}, port: 34_980])

    on_exit(fn ->
      _ = Simulator.stop()
    end)

    :ok
  end

  test "payload reports simulator status and configuration sync" do
    configured =
      SimulatorConfig.default_selected()
      |> SimulatorConfig.selected_entries()

    payload = SimulatorRuntime.payload(configured, [])

    assert payload.status == "running"
    assert payload.matches_selection
    assert payload.sync_tone == "info"
    assert payload.faults.active_count == 0
    assert Enum.find(payload.summary, &(&1.label == "UDP")).value == "127.0.0.2:34980"
  end

  test "payload warns when the running ring differs from the configured order" do
    configured =
      [
        %{"id" => "1", "driver" => "KinoEtherCAT.Driver.EK1100"},
        %{"id" => "2", "driver" => "KinoEtherCAT.Driver.EL2809"},
        %{"id" => "3", "driver" => "KinoEtherCAT.Driver.EL1809"}
      ]
      |> SimulatorConfig.selected_entries()

    payload = SimulatorRuntime.payload(configured, [])

    refute payload.matches_selection
    assert payload.sync_tone == "warn"
  end

  test "runtime actions clear faults and stop the simulator" do
    :ok = Simulator.inject_fault(:drop_responses)

    assert %{level: "info"} = SimulatorRuntime.perform("clear_faults")
    assert SimulatorRuntime.payload([], []).faults.active_count == 0

    assert %{level: "info"} = SimulatorRuntime.perform("stop_runtime")
    assert SimulatorRuntime.payload([], []).status == "offline"
  end
end
