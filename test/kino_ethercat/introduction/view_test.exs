defmodule KinoEtherCAT.Introduction.ViewTest do
  use ExUnit.Case, async: false

  alias EtherCAT.Simulator
  alias EtherCAT.Simulator.Slave
  alias KinoEtherCAT.Introduction.View

  setup do
    _ = Simulator.stop()

    devices = [
      Slave.from_driver(KinoEtherCAT.Driver.EK1100, name: :coupler),
      Slave.from_driver(KinoEtherCAT.Driver.EL1809, name: :inputs),
      Slave.from_driver(KinoEtherCAT.Driver.EL2809, name: :outputs)
    ]

    {:ok, _supervisor} =
      Simulator.start(devices: devices, udp: [ip: {127, 0, 0, 2}, port: 0])

    :ok = Simulator.connect({:outputs, :ch1}, {:inputs, :ch1})

    on_exit(fn ->
      _ = Simulator.stop()
    end)

    :ok
  end

  test "payload exposes a simplified learning path and playground" do
    payload = View.payload()

    assert payload.status == "running"
    assert Enum.find(payload.summary, &(&1.label == "Connections")).value == "1"

    assert Enum.find(payload.setup_workflow, &(&1.label == "Next step")).value =~
             "Setup smart cell"

    assert Enum.any?(payload.path, &String.starts_with?(&1.title, "1. Evaluate"))
    assert Enum.any?(payload.path, &String.starts_with?(&1.title, "4. Use the Master render"))
    assert Enum.any?(payload.state_overview, &(&1.label == "Master state"))

    assert [
             %{
               source_slave: "outputs",
               source_signal: "ch1",
               target_slave: "inputs",
               target_signal: "ch1",
               writable: true
             }
           ] = payload.playground.rows
  end

  test "perform updates the playground value view" do
    assert %{level: "info"} =
             View.perform("set_output", %{
               "slave" => "outputs",
               "signal" => "ch1",
               "value" => "1"
             })

    row = View.payload().playground.rows |> List.first()
    assert row.source_value == "1"
  end

  test "offline payload stays renderable without playground rows" do
    assert :ok = Simulator.stop()

    payload = View.payload()

    assert payload.status == "offline"
    assert payload.playground.rows == []

    assert Enum.find(payload.setup_workflow, &(&1.label == "First step")).value =~
             "Simulator smart cell"

    assert Enum.find(payload.summary, &(&1.label == "Domain")).value == "n/a"
  end
end
