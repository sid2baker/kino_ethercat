defmodule KinoEtherCAT.SmartCells.SimulatorRuntimeTest do
  use ExUnit.Case, async: false

  alias EtherCAT.Simulator
  alias EtherCAT.Simulator.Fault
  alias EtherCAT.Simulator.Slave
  alias EtherCAT.Simulator.Udp
  alias EtherCAT.Simulator.Udp.Fault, as: UdpFault
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

  test "runtime fault summary includes queued runtime and udp reply faults" do
    :ok = Simulator.inject_fault(Fault.drop_responses())
    :ok = Simulator.inject_fault(Fault.disconnect(:inputs) |> Fault.next(2))
    :ok = Udp.inject_fault(UdpFault.truncate() |> UdpFault.next(3))

    payload = SimulatorRuntime.payload([], [])

    assert payload.faults.runtime_sticky_count == 1
    assert payload.faults.runtime_pending_count >= 1
    assert payload.faults.udp_pending_count == 3

    assert payload.faults.active_count ==
             payload.faults.runtime_sticky_count +
               payload.faults.runtime_pending_count +
               payload.faults.udp_pending_count
  end

  test "runtime actions clear faults and stop the simulator" do
    :ok = Simulator.inject_fault(Fault.drop_responses())
    :ok = Udp.inject_fault(UdpFault.wrong_idx())

    assert %{level: "info"} = SimulatorRuntime.perform("clear_faults")
    assert SimulatorRuntime.payload([], []).faults.active_count == 0

    assert %{level: "info"} = SimulatorRuntime.perform("stop_runtime")
    assert SimulatorRuntime.payload([], []).status == "offline"
  end
end
