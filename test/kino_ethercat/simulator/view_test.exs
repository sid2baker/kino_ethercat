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

    {:ok, _supervisor} = Simulator.start(devices: devices)

    on_exit(fn ->
      _ = Simulator.stop()
    end)

    :ok
  end

  test "payload exposes simulator topology and fault state" do
    payload = View.payload()

    assert payload.status == "running"
    assert Enum.map(payload.slaves, & &1.name) == ["coupler", "inputs", "outputs"]
    assert Enum.find(payload.summary, &(&1.label == "Slaves")).value == "3"
    assert payload.faults == %{drop_responses?: false, wkc_offset: 0, disconnected: []}
  end

  test "perform updates coarse simulator faults and clears them again" do
    assert %{level: "info"} = View.perform("set_wkc_offset", %{"value" => "-2"})
    assert View.payload().faults.wkc_offset == -2

    assert %{level: "info"} = View.perform("inject_disconnect", %{"slave" => "inputs"})
    assert "inputs" in View.payload().faults.disconnected

    assert %{level: "info"} = View.perform("clear_faults", %{})
    assert View.payload().faults == %{drop_responses?: false, wkc_offset: 0, disconnected: []}
  end

  test "perform latches an al error on a selected slave" do
    assert %{level: "info"} =
             View.perform("inject_al_error", %{"slave" => "outputs", "code" => "0x0011"})

    outputs = Enum.find(View.payload().slaves, &(&1.name == "outputs"))

    assert outputs.al_error == "latched"
    assert outputs.al_status_code == "0x0011"
  end
end
