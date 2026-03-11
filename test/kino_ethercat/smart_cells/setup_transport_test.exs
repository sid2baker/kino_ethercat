defmodule KinoEtherCAT.SmartCells.SetupTransportTest do
  use ExUnit.Case, async: false

  alias EtherCAT.Simulator
  alias EtherCAT.Simulator.Slave
  alias KinoEtherCAT.SmartCells.SetupTransport

  setup do
    _ = Simulator.stop()

    on_exit(fn ->
      _ = Simulator.stop()
    end)

    :ok
  end

  test "auto mode adopts the running simulator udp endpoint" do
    devices = [
      Slave.from_driver(KinoEtherCAT.Driver.EK1100, name: :coupler),
      Slave.from_driver(KinoEtherCAT.Driver.EL1809, name: :inputs),
      Slave.from_driver(KinoEtherCAT.Driver.EL2809, name: :outputs)
    ]

    {:ok, _supervisor} = Simulator.start(devices: devices, udp: [ip: {127, 0, 0, 2}, port: 0])
    {:ok, %{udp: %{port: port}}} = Simulator.info()

    config = SetupTransport.normalize(%{})

    assert config.transport_mode == :auto
    assert config.transport == :udp
    assert config.host == "127.0.0.2"
    assert config.port == port
  end

  test "manual mode keeps the user transport selection even with a running simulator" do
    devices = [
      Slave.from_driver(KinoEtherCAT.Driver.EK1100, name: :coupler),
      Slave.from_driver(KinoEtherCAT.Driver.EL1809, name: :inputs)
    ]

    {:ok, _supervisor} = Simulator.start(devices: devices, udp: [ip: {127, 0, 0, 2}, port: 0])

    config =
      SetupTransport.normalize(%{
        "transport_mode" => "manual",
        "transport" => "raw",
        "interface" => "eth1"
      })

    assert config.transport_mode == :manual
    assert config.transport == :raw
    assert config.interface == "eth1"
  end
end
