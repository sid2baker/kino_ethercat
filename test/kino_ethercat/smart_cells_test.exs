defmodule KinoEtherCAT.SmartCellsTest do
  use ExUnit.Case, async: true

  alias KinoEtherCAT.SmartCells.{Setup, Simulator, Visualizer}

  test "setup cell persists static startup code from discovered slaves" do
    source =
      Setup.to_source(%{
        "interface" => "eth0",
        "domains" => [
          %{
            "id" => "fast",
            "cycle_time_ms" => 1,
            "miss_threshold" => 1_000
          },
          %{
            "id" => "slow",
            "cycle_time_ms" => 4,
            "miss_threshold" => 250
          }
        ],
        "dc_enabled" => true,
        "dc_cycle_ns" => 1_000_000,
        "await_lock" => true,
        "warmup_cycles" => 8,
        "slaves" => [
          %{
            "name" => "coupler",
            "discovered_name" => "coupler",
            "driver" => "",
            "domain_id" => ""
          },
          %{
            "name" => "slave_1",
            "discovered_name" => "slave_1",
            "driver" => "KinoEtherCAT.Driver.EL1809",
            "domain_id" => "fast"
          },
          %{
            "name" => "slave_2",
            "discovered_name" => "slave_2",
            "driver" => "KinoEtherCAT.Driver.EL2809",
            "domain_id" => "slow"
          }
        ]
      })

    assert source =~ ~s(interface: "eth0")

    assert source =~ ~s(%DomainConfig{id: :fast, cycle_time_us: 1000, miss_threshold: 1000})

    assert source =~ ~s(%DomainConfig{id: :slow, cycle_time_us: 4000, miss_threshold: 250})

    assert source =~ "slaves: ["
    assert source =~ ~s(%SlaveConfig{name: :coupler, target_state: :op})
    assert source =~ ~s(driver: KinoEtherCAT.Driver.EL1809)
    assert source =~ ~s(process_data: {:all, :fast})
    assert source =~ ~s(process_data: {:all, :slow})
    assert source =~ ~s(warmup_cycles: 8)
    assert source =~ ":ok = EtherCAT.await_operational()"
    assert source =~ "Kino.Layout.tabs("
    assert source =~ "Master: KinoEtherCAT.master()"
    assert source =~ ~s|"Task Manager": KinoEtherCAT.diagnostics()|
    refute source =~ "String.to_atom"
    refute source =~ "EtherCAT.configure_slave"
    refute source =~ "backup_interface"
    refute source =~ "activation_mode"
  end

  test "setup cell migrates legacy single-domain attrs into multi-domain startup config" do
    source =
      Setup.to_source(%{
        "interface" => "eth0",
        "domain_id" => "main",
        "cycle_time_us" => 1_000,
        "dc_enabled?" => false,
        "slaves" => [
          %{
            "name" => "sensor_a",
            "discovered_name" => "slave_1",
            "driver" => "KinoEtherCAT.Driver.EL1809",
            "domain_id" => "main"
          }
        ]
      })

    assert source =~ ~s(dc: nil)

    assert source =~ ~s(%DomainConfig{id: :main, cycle_time_us: 1000, miss_threshold: 1000})

    assert source =~ "%SlaveConfig{"
    assert source =~ "name: :sensor_a"
    assert source =~ "driver: KinoEtherCAT.Driver.EL1809"
    assert source =~ "process_data: {:all, :main}"
    assert source =~ "target_state: :op"

    refute source =~ "EtherCAT.configure_slave"
    refute source =~ "activation_mode"
  end

  test "visualizer cell renders string-based calls" do
    source =
      Visualizer.to_source(%{
        "columns" => 2,
        "selected" => [
          %{"name" => "sensor_a"},
          %{"name" => "output rack"}
        ]
      })

    assert source =~
             ~s/KinoEtherCAT.Widgets.dashboard([:sensor_a, :"output rack"], columns: 2) |> Kino.render()/

    assert source =~ "Kino.nothing()"
    refute source =~ "String.to_atom"
  end

  test "simulator cell renders a udp-backed loopback source" do
    source =
      Simulator.to_source(%{
        "master_ip" => "127.0.0.1",
        "simulator_ip" => "127.0.0.2",
        "cycle_time_ms" => "10"
      })

    assert source =~ "alias EtherCAT.Simulator"
    assert source =~ "Slave.from_driver(KinoEtherCAT.Driver.EK1100, name: :coupler)"
    assert source =~ "Slave.from_driver(KinoEtherCAT.Driver.EL1809, name: :inputs)"
    assert source =~ "Slave.from_driver(KinoEtherCAT.Driver.EL2809, name: :outputs)"
    assert source =~ "master_ip = {127, 0, 0, 1}"
    assert source =~ "simulator_ip = {127, 0, 0, 2}"
    assert source =~ "transport: :udp"
    assert source =~ "bind_ip: master_ip"
    assert source =~ "host: simulator_ip"
    assert source =~ "%DomainConfig{id: :main, cycle_time_us: cycle_time_ms * 1_000}"
    assert source =~ ~s|"Task Manager": KinoEtherCAT.diagnostics()|
    refute source =~ "String.to_atom"
  end
end
