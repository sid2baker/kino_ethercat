defmodule KinoEtherCAT.SlaveSnapshotTest do
  use ExUnit.Case, async: true

  alias KinoEtherCAT.Widgets.SlaveSnapshot

  test "builds a live snapshot with input and output sections" do
    info = %{
      name: :rack,
      station: 0x1001,
      al_state: :op,
      driver: KinoEtherCAT.Driver.EL1809,
      coe: true,
      configuration_error: nil,
      identity: %{
        vendor_id: 0x2,
        product_code: 0x0711_1389,
        revision: 0x0019_0000,
        serial_number: 0
      },
      signals: [
        %{name: :ch1, domain: :main, direction: :input, bit_size: 1},
        %{name: :temperature, domain: :main, direction: :input, bit_size: 16},
        %{name: :q1, domain: :main, direction: :output, bit_size: 1}
      ]
    }

    snapshot =
      SlaveSnapshot.build(
        :rack,
        info,
        %{ch1: {1, 101}, temperature: {:ok, 25.0}},
        [%{id: "main", state: "cycling", miss_count: 0, total_miss_count: 0, expected_wkc: 3}],
        nil,
        nil,
        []
      )

    assert snapshot.status == "live"
    assert snapshot.summary.name == "rack"
    assert snapshot.summary.driver == "KinoEtherCAT.Driver.EL1809"
    assert snapshot.summary.identity.vendor_id == 0x2

    assert [
             %{
               name: "ch1",
               active: true,
               display: "1",
               updated_at_us: 101,
               updated_at: updated_at
             }
             | _
           ] =
             snapshot.inputs

    assert is_binary(updated_at)

    assert Enum.any?(
             snapshot.inputs,
             &(&1.name == "temperature" and &1.display == "{:ok, 25.0}" and
                 &1.updated_at_us == nil)
           )

    assert [%{name: "q1", writable: true, display: "awaiting data"}] = snapshot.outputs
  end

  test "extracts input sample timestamps from read_input tuples" do
    info = %{
      name: :rack,
      station: 0x1001,
      al_state: :op,
      driver: KinoEtherCAT.Driver.EL1809,
      coe: true,
      configuration_error: nil,
      identity: nil,
      signals: [
        %{name: :ch1, domain: :main, direction: :input, bit_size: 1},
        %{name: :temperature, domain: :main, direction: :input, bit_size: 16}
      ]
    }

    snapshot =
      SlaveSnapshot.build(
        :rack,
        info,
        %{ch1: {1, 101}, temperature: {24.5, 202}},
        [],
        nil,
        nil,
        []
      )

    assert Enum.any?(
             snapshot.inputs,
             &(&1.name == "ch1" and &1.updated_at_us == 101 and is_binary(&1.updated_at) and
                 &1.display == "1")
           )

    assert Enum.any?(
             snapshot.inputs,
             &(&1.name == "temperature" and &1.updated_at_us == 202 and is_binary(&1.updated_at) and
                 &1.display == "24.5")
           )
  end

  test "builds an unavailable snapshot when the slave is missing" do
    snapshot =
      SlaveSnapshot.build(:ghost, nil, %{}, [], %{signal: "q1", reason: :enoent}, :not_found, [])

    assert snapshot.status == "unavailable"
    assert snapshot.summary.name == "ghost"
    assert snapshot.runtime_error == ":not_found"
    assert snapshot.write_error == %{signal: "q1", reason: ":enoent"}
  end
end
