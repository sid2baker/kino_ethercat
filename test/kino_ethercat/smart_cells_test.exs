defmodule KinoEtherCAT.SmartCellsTest do
  use ExUnit.Case, async: true

  alias KinoEtherCAT.{SetupCell, VisualizerCell}

  test "setup cell renders dynamic PREOP source when discovery names are unchanged" do
    source =
      SetupCell.to_source(%{
        "interface" => "eth0",
        "domain_id" => "main",
        "cycle_time_us" => 2_000,
        "backup_interface" => "eth1",
        "dc_enabled?" => true,
        "await_lock?" => true,
        "activation_mode" => "op",
        "slaves" => [
          %{
            "name" => "coupler",
            "discovered_name" => "coupler",
            "driver" => ""
          },
          %{
            "name" => "slave_1",
            "discovered_name" => "slave_1",
            "driver" => "KinoEtherCAT.Driver.EL1809"
          }
        ]
      })

    assert source =~ ~s(interface: "eth0")
    assert source =~ ~s(backup_interface: "eth1")
    assert source =~ ~s(%DomainConfig{id: :"main", cycle_time_us: 2000})
    assert source =~ "EtherCAT.configure_slave("
    assert source =~ ~s(:"coupler")
    assert source =~ ~s(driver: KinoEtherCAT.Driver.EL1809)
    assert source =~ ~s(process_data: {:all, :"main"})
    assert source =~ ":ok = EtherCAT.activate()"
    assert source =~ ":ok = EtherCAT.await_operational()"
    refute source =~ "String.to_atom"
    refute source =~ "slaves: ["
  end

  test "setup cell falls back to declarative startup when slave names are renamed" do
    source =
      SetupCell.to_source(%{
        "interface" => "eth0",
        "domain_id" => "main",
        "cycle_time_us" => 1_000,
        "dc_enabled?" => false,
        "activation_mode" => "preop",
        "slaves" => [
          %{
            "name" => "sensor_a",
            "discovered_name" => "slave_1",
            "driver" => "KinoEtherCAT.Driver.EL1809"
          }
        ]
      })

    assert source =~ "Uses declarative startup"
    assert source =~ ~s(dc: nil)

    assert source =~
             ~s(%SlaveConfig{name: :"sensor_a", driver: KinoEtherCAT.Driver.EL1809, process_data: {:all, :"main"}, target_state: :preop})

    refute source =~ "EtherCAT.configure_slave"
    refute source =~ "EtherCAT.activate()"
  end

  test "visualizer cell renders string-based calls" do
    source =
      VisualizerCell.to_source(%{
        "columns" => 2,
        "selected" => [
          %{"name" => "sensor_a"},
          %{"name" => "output rack"}
        ]
      })

    assert source =~ ~s/KinoEtherCAT.dashboard([:"sensor_a", :"output rack"], columns: 2) |> Kino.render()/
    assert source =~ "Kino.nothing()"
    refute source =~ "String.to_atom"
  end
end
