defmodule KinoEtherCAT.Simulator.FaultsViewTest do
  use ExUnit.Case, async: false

  alias EtherCAT.Simulator
  alias EtherCAT.Simulator.Slave
  alias KinoEtherCAT.Simulator.FaultsView

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

  test "payload exposes split runtime and udp fault state" do
    payload = FaultsView.payload()

    assert payload.status == "running"
    assert payload.runtime_faults.active_count == 0
    assert payload.udp_faults.enabled
    assert payload.udp_faults.active_count == 0
    assert payload.slave_options == ["coupler", "inputs", "outputs"]
  end

  test "perform updates queued runtime faults and queued udp reply faults" do
    assert %{level: "info"} = FaultsView.perform("set_wkc_offset", %{"value" => "-2"})
    assert FaultsView.payload().runtime_faults.wkc_offset == -2

    assert %{level: "info"} =
             FaultsView.perform("queue_runtime_fault", %{
               "kind" => "disconnect",
               "plan" => "count",
               "count" => "2",
               "slave" => "inputs"
             })

    payload = FaultsView.payload()
    assert payload.runtime_faults.pending_count == 2
    assert payload.runtime_faults.next_label == "disconnect inputs"

    assert %{level: "info"} =
             FaultsView.perform("queue_udp_fault", %{
               "mode" => "wrong_idx",
               "plan" => "count",
               "count" => "3"
             })

    payload = FaultsView.payload()
    assert payload.udp_faults.active_count == 3
    assert payload.udp_faults.next_label == "wrong datagram index"

    assert %{level: "info"} = FaultsView.perform("clear_faults", %{})

    payload = FaultsView.payload()
    assert payload.runtime_faults.active_count == 0
    assert payload.udp_faults.active_count == 0
  end

  test "perform latches an al error on a selected slave" do
    assert %{level: "info"} =
             FaultsView.perform("inject_al_error", %{"slave" => "outputs", "code" => "0x0011"})

    outputs = Enum.find(FaultsView.payload().slaves, &(&1.name == "outputs"))

    assert outputs.al_error == "latched"
    assert outputs.al_status_code == "0x0011"
  end
end
