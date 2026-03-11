defmodule KinoEtherCAT.Simulator.ViewTest do
  use ExUnit.Case, async: false

  alias EtherCAT.Simulator
  alias EtherCAT.Simulator.Slave
  alias KinoEtherCAT.Simulator.View

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
end
