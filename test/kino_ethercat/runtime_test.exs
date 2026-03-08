defmodule KinoEtherCAT.RuntimeTest do
  use ExUnit.Case, async: true

  alias EtherCAT.{Bus, Domain, Master, Slave}
  alias EtherCAT.DC.Status, as: DCStatus
  alias KinoEtherCAT.Runtime

  test "resource accessors always return EtherCAT structs" do
    assert %Master{} = KinoEtherCAT.master()
    assert %Slave{name: :rack_1} = KinoEtherCAT.slave(:rack_1)
    assert %Domain{id: :main} = KinoEtherCAT.domain(:main)
    assert %Bus{} = KinoEtherCAT.bus()
    assert %DCStatus{} = KinoEtherCAT.dc()
  end

  test "runtime payloads expose top-level controls and degrade gracefully when not started" do
    assert %{kind: "master", controls: %{buttons: buttons}} = Runtime.payload(%Master{})
    assert Enum.any?(buttons, &(&1.id == "activate"))

    assert %{kind: "slave", status: "unavailable"} =
             Runtime.payload(%Slave{name: :rack_1})

    assert %{kind: "domain", status: "unavailable"} =
             Runtime.payload(%Domain{id: :main})

    assert %{kind: "bus", controls: %{submit: %{id: "set_frame_timeout"}}} =
             Runtime.payload(%Bus{})

    assert %{kind: "dc", controls: %{submit: %{id: "await_dc_locked"}}} =
             Runtime.payload(%DCStatus{})
  end

  test "runtime actions validate numeric inputs before touching EtherCAT" do
    assert {:error, %Bus{}, %{level: "error", text: ":invalid_integer"}} =
             Runtime.perform(%Bus{}, "set_frame_timeout", %{"value" => "abc"})

    assert {:error, %Domain{id: :main}, %{level: "error", text: ":invalid_integer"}} =
             Runtime.perform(%Domain{id: :main}, "update_cycle_time", %{"value" => "0"})

    assert {:error, %DCStatus{}, %{level: "error", text: ":invalid_integer"}} =
             Runtime.perform(%DCStatus{}, "await_dc_locked", %{"value" => "-1"})

    assert {:error, %Slave{name: :rack_1}, %{level: "error", text: ":invalid_transition"}} =
             Runtime.perform(%Slave{name: :rack_1}, "transition", %{"value" => "invalid"})
  end
end
