defmodule KinoEtherCAT.Simulator.FaultsViewTest do
  use ExUnit.Case, async: false

  alias EtherCAT.Simulator
  alias EtherCAT.Simulator.Slave
  alias KinoEtherCAT.Simulator.FaultsView
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

  test "payload exposes split runtime and transport fault state" do
    payload = FaultsView.payload()

    assert payload.status == "running"
    assert payload.runtime_faults.active_count == 0
    assert payload.runtime_faults.scheduled_count == 0
    assert payload.transport_faults.enabled
    assert payload.transport_faults.transport == "udp"
    assert payload.transport_faults.active_count == 0
    assert payload.slave_options == ["coupler", "inputs", "outputs"]
  end

  test "perform updates richer runtime faults, scheduled faults, and transport scripts" do
    assert %{level: "info"} =
             FaultsView.perform("apply_runtime_fault", %{
               "kind" => "command_wkc_offset",
               "command" => "lrw",
               "value" => "2"
             })

    payload = FaultsView.payload()
    assert payload.runtime_faults.active_count == 1

    assert payload.runtime_faults.command_offsets == [
             %{command: "lrw", delta: 2, label: "command lrw WKC offset 2"}
           ]

    assert "command lrw WKC offset 2" in payload.runtime_faults.sticky_labels

    assert %{level: "info"} =
             FaultsView.perform("apply_runtime_fault", %{
               "kind" => "disconnect",
               "plan" => "after_milestone",
               "slave" => "inputs",
               "milestone_kind" => "healthy_exchanges",
               "milestone_count" => "2"
             })

    payload = FaultsView.payload()
    assert payload.runtime_faults.scheduled_count == 1
    assert payload.runtime_faults.pending_count == 0
    assert payload.runtime_faults.next_label == nil

    assert payload.runtime_faults.scheduled_faults == [
             %{
               key: "scheduled-0",
               label: "disconnect inputs",
               schedule: "after 2 healthy exchanges",
               remaining: "2"
             }
           ]

    assert %{level: "info"} =
             FaultsView.perform("apply_transport_fault", %{
               "transport" => "udp",
               "mode" => "wrong_idx",
               "plan" => "script",
               "script" => "truncate, wrong_idx, replay_previous"
             })

    payload = FaultsView.payload()
    assert payload.transport_faults.transport == "udp"
    assert payload.transport_faults.active_count == 3
    assert payload.transport_faults.next_label == "truncate"

    assert payload.transport_faults.pending_labels == [
             "truncate",
             "wrong index",
             "replay previous response"
           ]

    assert %{level: "info"} = FaultsView.perform("clear_faults", %{})

    payload = FaultsView.payload()
    assert payload.runtime_faults.active_count == 0
    assert payload.runtime_faults.scheduled_count == 0
    assert payload.transport_faults.active_count == 0
  end

  test "perform latches an al error on a selected slave" do
    assert %{level: "info"} =
             FaultsView.perform("apply_runtime_fault", %{
               "kind" => "latch_al_error",
               "slave" => "outputs",
               "code" => "0x0011"
             })

    outputs = Enum.find(FaultsView.payload().slaves, &(&1.name == "outputs"))

    assert outputs.al_error == "latched"
    assert outputs.al_status_code == "0x0011"
  end

  test "payload marks transport faults disabled when simulator has no external transport" do
    _ = Simulator.stop()

    devices = [
      Slave.from_driver(KinoEtherCAT.Driver.EK1100, name: :coupler),
      Slave.from_driver(KinoEtherCAT.Driver.EL1809, name: :inputs),
      Slave.from_driver(KinoEtherCAT.Driver.EL2809, name: :outputs)
    ]

    {:ok, _supervisor} = Simulator.start(devices: devices)

    payload = FaultsView.payload()

    assert payload.transport_faults.enabled == false
    assert payload.transport_faults.summary == "Transport fault injection unavailable."
    assert Enum.all?(payload.summary, &(&1.label != "Transport faults"))
  end

  test "payload exposes raw transport faults when raw transport is running" do
    if transport_available?("raw_socket") do
      _ = Simulator.stop()

      devices = [
        Slave.from_driver(KinoEtherCAT.Driver.EK1100, name: :coupler),
        Slave.from_driver(KinoEtherCAT.Driver.EL1809, name: :inputs),
        Slave.from_driver(KinoEtherCAT.Driver.EL2809, name: :outputs)
      ]

      {:ok, _supervisor} = Simulator.start(devices: devices, raw: [interface: "veth-s0"])

      payload = FaultsView.payload()

      assert payload.transport_faults.enabled
      assert payload.transport_faults.transport == "raw"
      assert payload.transport_faults.mode == "single"
      assert payload.transport_faults.active_count == 0

      assert %{level: "info"} =
               FaultsView.perform("apply_transport_fault", %{
                 "transport" => "raw",
                 "kind" => "delay_response",
                 "delay_ms" => "75",
                 "endpoint" => "all",
                 "from_ingress" => "all"
               })

      payload = FaultsView.payload()

      assert payload.transport_faults.active_count == 1

      assert [
               %{
                 endpoint: "primary",
                 response_delay_ms: 75,
                 response_delay_from_ingress: "all",
                 active: true
               }
             ] = payload.transport_faults.endpoints

      assert %{level: "info"} = FaultsView.perform("clear_transport_faults", %{})
      assert FaultsView.payload().transport_faults.active_count == 0
    else
      assert true
    end
  end

  defp transport_available?(value) do
    SimulatorConfig.available_transports()
    |> Enum.any?(&(&1.value == value and &1.available))
  end
end
