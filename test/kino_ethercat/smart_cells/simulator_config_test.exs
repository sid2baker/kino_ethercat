defmodule KinoEtherCAT.SmartCells.SimulatorConfigTest do
  use ExUnit.Case, async: true

  alias KinoEtherCAT.SmartCells.SimulatorConfig

  test "fresh simulator config seeds one default ch1 loopback connection" do
    config = SimulatorConfig.normalize(%{})

    assert config.connections == [
             %{
               "source_id" => "3",
               "source_signal" => "ch1",
               "target_id" => "2",
               "target_signal" => "ch1"
             }
           ]
  end

  test "auto-wire matching connects output and input channels with the same name" do
    {connections, stats} =
      SimulatorConfig.auto_wire_matching([
        %{"id" => "1", "driver" => "KinoEtherCAT.Driver.EK1100"},
        %{"id" => "2", "driver" => "KinoEtherCAT.Driver.EL2809"},
        %{"id" => "3", "driver" => "KinoEtherCAT.Driver.EL1809"}
      ])

    assert stats.matched == 16
    assert Enum.any?(connections, &(&1["source_id"] == "2" and &1["source_signal"] == "ch1"))
    assert Enum.any?(connections, &(&1["target_id"] == "3" and &1["target_signal"] == "ch16"))
    assert Enum.take(Enum.map(connections, & &1["source_signal"]), 3) == ["ch1", "ch2", "ch3"]
  end

  test "normalize drops invalid connections for removed devices" do
    config =
      SimulatorConfig.normalize(%{
        "selected" => [
          %{"id" => "1", "driver" => "KinoEtherCAT.Driver.EK1100"},
          %{"id" => "2", "driver" => "KinoEtherCAT.Driver.EL2809"}
        ],
        "connections" => [
          %{
            "source_id" => "2",
            "source_signal" => "ch1",
            "target_id" => "3",
            "target_signal" => "ch1"
          }
        ]
      })

    assert config.connections == []
  end

  test "normalize preserves custom names and keeps them unique" do
    config =
      SimulatorConfig.normalize(%{
        "selected" => [
          %{"id" => "1", "driver" => "KinoEtherCAT.Driver.EK1100", "name" => "rack"},
          %{"id" => "2", "driver" => "KinoEtherCAT.Driver.EL2809", "name" => "rack"},
          %{"id" => "3", "driver" => "KinoEtherCAT.Driver.EL1809", "name" => "  "}
        ]
      })

    assert Enum.map(config.selected, & &1["name"]) == ["rack", "rack_2", "inputs"]
  end

  test "connection entries use stable id-based keys for removal" do
    entries =
      SimulatorConfig.connection_entries(
        [
          %{"id" => "1", "driver" => "KinoEtherCAT.Driver.EK1100"},
          %{"id" => "2", "driver" => "KinoEtherCAT.Driver.EL2809", "name" => "left_outputs"},
          %{"id" => "3", "driver" => "KinoEtherCAT.Driver.EL1809", "name" => "left_inputs"}
        ],
        [
          %{
            "source_id" => "2",
            "source_signal" => "ch1",
            "target_id" => "3",
            "target_signal" => "ch1"
          }
        ]
      )

    assert [
             %{
               key: "2.ch1->3.ch1",
               source_label: "left_outputs.ch1",
               target_label: "left_inputs.ch1"
             }
           ] =
             entries
  end
end
