defmodule KinoEtherCAT.RuntimeTest do
  use ExUnit.Case, async: true

  alias EtherCAT.{Bus, Domain, Master, Slave}
  alias KinoEtherCAT.Runtime

  test "resource accessors always return EtherCAT structs" do
    assert %Master{} = KinoEtherCAT.master()
    assert %Slave{name: :rack_1} = KinoEtherCAT.slave(:rack_1)
    assert %Domain{id: :main} = KinoEtherCAT.domain(:main)
    assert %Bus{} = KinoEtherCAT.bus()
    assert dc_resource?(KinoEtherCAT.dc())
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
             Runtime.payload(default_dc_resource())
  end

  test "runtime actions validate numeric inputs before touching EtherCAT" do
    assert {:error, %Bus{}, %{level: "error", text: ":invalid_integer"}} =
             Runtime.perform(%Bus{}, "set_frame_timeout", %{"value" => "abc"})

    assert {:error, %Domain{id: :main}, %{level: "error", text: ":invalid_integer"}} =
             Runtime.perform(%Domain{id: :main}, "update_cycle_time", %{"value" => "0"})

    assert {:error, dc_resource, %{level: "error", text: ":invalid_integer"}} =
             Runtime.perform(default_dc_resource(), "await_dc_locked", %{"value" => "-1"})

    assert dc_resource?(dc_resource)

    assert {:error, %Slave{name: :rack_1}, %{level: "error", text: ":invalid_transition"}} =
             Runtime.perform(%Slave{name: :rack_1}, "transition", %{"value" => "invalid"})
  end

  defp default_dc_resource do
    cond do
      function_exported?(EtherCAT.DC.Status, :__struct__, 0) -> struct(EtherCAT.DC.Status)
      function_exported?(EtherCAT.DC, :__struct__, 0) -> struct(EtherCAT.DC)
      true -> %{}
    end
  end

  defp dc_resource?(resource) do
    is_struct(resource, EtherCAT.DC.Status) or is_struct(resource, EtherCAT.DC)
  end
end
