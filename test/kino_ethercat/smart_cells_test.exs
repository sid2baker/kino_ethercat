defmodule KinoEtherCAT.SmartCellsTest do
  use ExUnit.Case, async: true

  alias KinoEtherCAT.{SetupCell, VisualizerCell}

  test "setup cell renders safe string source" do
    source =
      SetupCell.to_source(%{
        "interface" => "eth0",
        "domain_id" => "main",
        "cycle_time_us" => 2_000,
        "slaves" => [
          %{"name" => "sensor_a", "driver" => "KinoEtherCAT.Driver.EL1809"},
          %{"name" => "  output rack  ", "driver" => "not valid"}
        ]
      })

    assert source =~ ~s(interface: "eth0")
    assert source =~ ~s(%DomainConfig{id: :"main", cycle_time_us: 2000})

    assert source =~
             ~s(%SlaveConfig{name: :"sensor_a", driver: KinoEtherCAT.Driver.EL1809, process_data: {:all, :"main"}})

    assert source =~ ~s(%SlaveConfig{name: :"output rack"})
    refute source =~ "String.to_atom"
  end

  test "visualizer cell renders string-based calls" do
    source =
      VisualizerCell.to_source(%{
        "selected" => [
          %{"name" => "sensor_a", "columns" => 4},
          %{"name" => "output rack", "columns" => nil}
        ]
      })

    assert source =~ ~s/KinoEtherCAT.render(:"sensor_a", columns: 4) |> Kino.render()/
    assert source =~ ~s/KinoEtherCAT.render(:"output rack") |> Kino.render()/
    assert source =~ "Kino.nothing()"
    refute source =~ "String.to_atom"
  end
end
