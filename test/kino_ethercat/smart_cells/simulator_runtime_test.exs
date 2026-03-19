defmodule KinoEtherCAT.SmartCells.SimulatorRuntimeTest do
  use ExUnit.Case, async: false

  alias EtherCAT.Simulator
  alias EtherCAT.Simulator.Fault
  alias EtherCAT.Simulator.Slave
  alias EtherCAT.Simulator.Transport.{Raw, Udp}
  alias EtherCAT.Simulator.Transport.Raw.Fault, as: RawFault
  alias EtherCAT.Simulator.Transport.Udp.Fault, as: UdpFault
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

    payload = SimulatorRuntime.payload(configured, [], "udp")

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

    payload = SimulatorRuntime.payload(configured, [], "udp")

    refute payload.matches_selection
    assert payload.sync_tone == "warn"
  end

  test "runtime fault summary includes queued runtime and transport faults" do
    :ok = Simulator.inject_fault(Fault.drop_responses())
    :ok = Simulator.inject_fault(Fault.disconnect(:inputs) |> Fault.next(2))
    :ok = Udp.inject_fault(UdpFault.truncate() |> UdpFault.next(3))

    payload = SimulatorRuntime.payload([], [], "udp")

    assert payload.faults.runtime_sticky_count == 1
    assert payload.faults.transport_fault_count == 3
    assert payload.faults.summary =~ "runtime"
    assert payload.faults.summary =~ "transport active"

    assert payload.faults.active_count >=
             payload.faults.runtime_sticky_count + payload.faults.transport_fault_count
  end

  test "runtime actions clear faults and stop the simulator" do
    :ok = Simulator.inject_fault(Fault.drop_responses())
    :ok = Udp.inject_fault(UdpFault.wrong_idx())

    assert %{level: "info"} = SimulatorRuntime.perform("clear_faults")
    assert SimulatorRuntime.payload([], [], "udp").faults.active_count == 0

    assert %{level: "info"} = SimulatorRuntime.perform("stop_runtime")
    assert SimulatorRuntime.payload([], [], "udp").status == "offline"
  end

  test "runtime actions clear raw transport delay faults" do
    if transport_available?("raw_socket") do
      _ = Simulator.stop()

      devices = [
        Slave.from_driver(KinoEtherCAT.Driver.EK1100, name: :coupler),
        Slave.from_driver(KinoEtherCAT.Driver.EL1809, name: :inputs),
        Slave.from_driver(KinoEtherCAT.Driver.EL2809, name: :outputs)
      ]

      {:ok, _supervisor} = Simulator.start(devices: devices, raw: [interface: "veth-s0"])
      :ok = Raw.inject_fault(RawFault.delay_response(75))

      assert SimulatorRuntime.payload([], [], "raw_socket").faults.transport_fault_count == 1
      assert %{level: "info"} = SimulatorRuntime.perform("clear_faults")
      assert SimulatorRuntime.payload([], [], "raw_socket").faults.transport_fault_count == 0
    else
      assert true
    end
  end

  test "payload warns when configured transport differs from the running simulator" do
    configured =
      SimulatorConfig.default_selected()
      |> SimulatorConfig.selected_entries()

    payload = SimulatorRuntime.payload(configured, [], "raw_socket")

    refute payload.matches_selection
    assert payload.running_transport == "udp"
    assert payload.configured_transport == "raw_socket"
    assert payload.sync_tone == "warn"
  end

  test "payload reports disabled when simulator has no external transport" do
    _ = Simulator.stop()

    devices = [
      Slave.from_driver(KinoEtherCAT.Driver.EK1100, name: :coupler),
      Slave.from_driver(KinoEtherCAT.Driver.EL1809, name: :inputs),
      Slave.from_driver(KinoEtherCAT.Driver.EL2809, name: :outputs)
    ]

    {:ok, _supervisor} = Simulator.start(devices: devices)

    configured =
      SimulatorConfig.default_selected()
      |> SimulatorConfig.selected_entries()

    payload = SimulatorRuntime.payload(configured, [], "raw_socket_redundant")

    assert payload.running_transport == "disabled"
    assert Enum.find(payload.summary, &(&1.label == "Transport")).value == "disabled"
    assert payload.sync_tone == "warn"
  end

  test "payload reports raw socket transport when raw simulator is running" do
    if transport_available?("raw_socket") do
      _ = Simulator.stop()

      devices = [
        Slave.from_driver(KinoEtherCAT.Driver.EK1100, name: :coupler),
        Slave.from_driver(KinoEtherCAT.Driver.EL1809, name: :inputs),
        Slave.from_driver(KinoEtherCAT.Driver.EL2809, name: :outputs)
      ]

      {:ok, _supervisor} = Simulator.start(devices: devices, raw: [interface: "veth-s0"])

      configured =
        SimulatorConfig.default_selected()
        |> SimulatorConfig.selected_entries()

      payload = SimulatorRuntime.payload(configured, [], "raw_socket")

      assert payload.running_transport == "raw_socket"
      assert Enum.find(payload.summary, &(&1.label == "Raw (primary)")).value == "veth-s0"
      assert payload.sync_tone == "info"
    else
      assert true
    end
  end

  test "payload reports redundant raw transport when redundant simulator is running" do
    if transport_available?("raw_socket_redundant") do
      _ = Simulator.stop()

      devices = [
        Slave.from_driver(KinoEtherCAT.Driver.EK1100, name: :coupler),
        Slave.from_driver(KinoEtherCAT.Driver.EL1809, name: :inputs),
        Slave.from_driver(KinoEtherCAT.Driver.EL2809, name: :outputs)
      ]

      {:ok, _supervisor} =
        Simulator.start(
          devices: devices,
          topology: :redundant,
          raw: [primary: [interface: "veth-s0"], secondary: [interface: "veth-s1"]]
        )

      configured =
        SimulatorConfig.default_selected()
        |> SimulatorConfig.selected_entries()

      payload = SimulatorRuntime.payload(configured, [], "raw_socket_redundant")

      assert payload.running_transport == "raw_socket_redundant"
      assert Enum.find(payload.summary, &(&1.label == "Raw (primary)")).value == "veth-s0"
      assert Enum.find(payload.summary, &(&1.label == "Raw (secondary)")).value == "veth-s1"
      assert payload.sync_tone == "info"
    else
      assert true
    end
  end

  defp transport_available?(value) do
    SimulatorConfig.available_transports()
    |> Enum.any?(&(&1.value == value and &1.available))
  end
end
