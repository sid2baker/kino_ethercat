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

  test "auto mode switches redundant defaults back to single raw when the simulator is single raw" do
    if transport_available?("raw_socket") do
      devices = [
        Slave.from_driver(KinoEtherCAT.Driver.EK1100, name: :coupler),
        Slave.from_driver(KinoEtherCAT.Driver.EL1809, name: :inputs),
        Slave.from_driver(KinoEtherCAT.Driver.EL2809, name: :outputs)
      ]

      {:ok, _supervisor} = Simulator.start(devices: devices, raw: [interface: "veth-s0"])

      config =
        SetupTransport.normalize(%{
          "transport_mode" => "auto",
          "transport" => "raw_redundant",
          "interface" => "eth0",
          "backup_interface" => "eth1"
        })

      assert config.transport_mode == :auto
      assert config.transport == :raw
      assert config.interface == "veth-m0"
    else
      assert true
    end
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

  test "auto mode only seeds the simulator endpoint while the transport is still at defaults" do
    devices = [
      Slave.from_driver(KinoEtherCAT.Driver.EK1100, name: :coupler),
      Slave.from_driver(KinoEtherCAT.Driver.EL1809, name: :inputs)
    ]

    {:ok, _supervisor} =
      Simulator.start(devices: devices, udp: [ip: {127, 0, 0, 2}, port: 34_980])

    config =
      SetupTransport.refresh_auto(%{
        transport_mode: :auto,
        transport: :udp,
        host: "127.0.0.2",
        port: 40_000,
        interface: "eth0"
      })

    assert config.transport == :udp
    assert config.host == "127.0.0.2"
    assert config.port == 40_000
  end

  test "source config supports redundant raw transport" do
    assert {:ok,
            %{
              transport: :raw_redundant,
              interface: "eth0",
              backup_interface: "eth1",
              host: nil,
              bind_ip: nil
            }} =
             SetupTransport.source_config(%{
               transport_mode: :manual,
               transport: :raw_redundant,
               interface: "eth0",
               backup_interface: "eth1",
               host: "127.0.0.2",
               port: 0x88A4
             })

    assert SetupTransport.summary_label(%{
             transport_mode: :manual,
             transport: :raw_redundant,
             interface: "eth0",
             backup_interface: "eth1",
             host: "127.0.0.2",
             port: 0x88A4
           }) == "eth0 + eth1"
  end

  defp transport_available?(value) do
    KinoEtherCAT.SmartCells.SimulatorConfig.available_transports()
    |> Enum.any?(&(&1.value == value and &1.available))
  end
end
