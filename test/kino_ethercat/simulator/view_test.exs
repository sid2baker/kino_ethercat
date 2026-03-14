defmodule KinoEtherCAT.Simulator.ViewTest do
  use ExUnit.Case, async: false

  alias EtherCAT.Simulator
  alias EtherCAT.Simulator.Slave
  alias KinoEtherCAT.Simulator.View
  alias KinoEtherCAT.SmartCells.SimulatorConfig

  setup do
    _ = Simulator.stop()

    devices = [
      Slave.from_driver(KinoEtherCAT.Driver.EK1100, name: :coupler),
      Slave.from_driver(KinoEtherCAT.Driver.EL1809, name: :inputs),
      Slave.from_driver(KinoEtherCAT.Driver.EL2809, name: :outputs)
    ]

    {:ok, _supervisor} =
      Simulator.start(devices: devices, udp: [ip: {127, 0, 0, 2}, port: 0])

    on_exit(fn ->
      _ = Simulator.stop()
    end)

    :ok
  end

  test "payload exposes simulator topology and fault summary" do
    payload = View.payload()

    assert payload.status == "running"
    assert Enum.map(payload.slaves, & &1.name) == ["coupler", "inputs", "outputs"]
    assert Enum.find(payload.summary, &(&1.label == "Slaves")).value == "3"
    assert payload.runtime_faults.active_count == 0
    assert payload.udp_faults.enabled
    assert payload.udp_faults.active_count == 0

    assert payload.fault_summary == [
             %{label: "Runtime", value: "No runtime faults."},
             %{label: "Next runtime", value: "none"},
             %{label: "UDP", value: "No queued UDP reply faults."},
             %{label: "Next UDP", value: "none"}
           ]
  end

  test "payload omits udp summary when simulator transport is disabled" do
    _ = Simulator.stop()

    devices = [
      Slave.from_driver(KinoEtherCAT.Driver.EK1100, name: :coupler),
      Slave.from_driver(KinoEtherCAT.Driver.EL1809, name: :inputs),
      Slave.from_driver(KinoEtherCAT.Driver.EL2809, name: :outputs)
    ]

    {:ok, _supervisor} = Simulator.start(devices: devices)

    payload = View.payload()

    assert Enum.find(payload.summary, &(&1.label == "Transport")).value == "disabled"
    assert Enum.all?(payload.summary, &(&1.label != "UDP faults"))
    assert payload.udp_faults.enabled == false

    assert payload.fault_summary == [
             %{label: "Runtime", value: "No runtime faults."},
             %{label: "Next runtime", value: "none"}
           ]
  end

  test "payload shows raw socket transport when raw simulator is running" do
    if transport_available?("raw_socket") do
      _ = Simulator.stop()

      devices = [
        Slave.from_driver(KinoEtherCAT.Driver.EK1100, name: :coupler),
        Slave.from_driver(KinoEtherCAT.Driver.EL1809, name: :inputs),
        Slave.from_driver(KinoEtherCAT.Driver.EL2809, name: :outputs)
      ]

      {:ok, _supervisor} = Simulator.start(devices: devices, raw: [interface: "veth-s0"])

      payload = View.payload()

      assert Enum.find(payload.summary, &(&1.label == "Raw (primary)")).value == "veth-s0"
      assert Enum.find(payload.summary, &(&1.label == "Topology")).value == "linear"
    else
      assert true
    end
  end

  test "payload shows redundant raw transport when redundant simulator is running" do
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

      payload = View.payload()

      assert Enum.find(payload.summary, &(&1.label == "Raw (primary)")).value == "veth-s0"
      assert Enum.find(payload.summary, &(&1.label == "Raw (secondary)")).value == "veth-s1"
      assert Enum.find(payload.summary, &(&1.label == "Topology")).value == "redundant"
    else
      assert true
    end
  end

  defp transport_available?(value) do
    SimulatorConfig.available_transports()
    |> Enum.any?(&(&1.value == value and &1.available))
  end
end
