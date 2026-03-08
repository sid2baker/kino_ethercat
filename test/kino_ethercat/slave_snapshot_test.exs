defmodule KinoEtherCAT.SlaveSnapshotTest do
  use ExUnit.Case, async: true

  alias KinoEtherCAT.SlaveSnapshot

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
        %{ch1: 1, temperature: {:ok, 25.0}},
        [%{id: "main", state: "cycling", miss_count: 0, total_miss_count: 0, expected_wkc: 3}],
        nil,
        nil,
        []
      )

    assert snapshot.status == "live"
    assert snapshot.summary.name == "rack"
    assert snapshot.summary.driver == "KinoEtherCAT.Driver.EL1809"
    assert snapshot.summary.identity.vendor_id == 0x2
    assert [%{name: "ch1", active: true, display: "1"} | _] = snapshot.inputs
    assert Enum.any?(snapshot.inputs, &(&1.name == "temperature" and &1.display == "{:ok, 25.0}"))
    assert [%{name: "q1", writable: true, display: "awaiting data"}] = snapshot.outputs
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
