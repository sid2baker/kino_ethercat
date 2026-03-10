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

  test "dc status resources stay renderable" do
    if Code.ensure_loaded?(EtherCAT.DC.Status) and
         function_exported?(EtherCAT.DC.Status, :__struct__, 0) do
      assert not is_nil(Kino.Render.impl_for(struct(EtherCAT.DC.Status)))
    end
  end

  test "dc resources render with an overview and raw fallback" do
    Application.ensure_all_started(:kino)

    assert %{type: :tabs, labels: ["Overview", "Raw"], outputs: [overview, raw]} =
             Kino.Render.to_livebook(default_dc_resource())

    assert %{type: :js} = overview
    assert %{type: :terminal_text} = raw
  end

  test "runtime payloads expose top-level controls and degrade gracefully when not started" do
    assert %{kind: "master", controls: %{buttons: buttons, select: select}} =
             Runtime.payload(%Master{})

    assert Enum.any?(buttons, &(&1.id == "activate"))
    assert select.id == "set_log_level"
    assert select.label == "Elixir log level"
    assert select.value in select.options

    assert %{kind: "slave", status: "unavailable"} =
             Runtime.payload(%Slave{name: :rack_1})

    assert %{kind: "domain", status: "unavailable"} =
             Runtime.payload(%Domain{id: :main})

    assert %{kind: "bus", controls: %{submit: %{id: "set_frame_timeout"}}} =
             Runtime.payload(struct(Bus))

    assert %{kind: "dc", controls: %{submit: %{id: "await_dc_locked"}}} =
             Runtime.payload(default_dc_resource())
  end

  test "runtime actions validate numeric inputs before touching EtherCAT" do
    bus = struct(Bus)

    assert {:error, ^bus, %{level: "error", text: ":invalid_integer"}} =
             Runtime.perform(bus, "set_frame_timeout", %{"value" => "abc"})

    assert {:error, %Domain{id: :main}, %{level: "error", text: ":invalid_integer"}} =
             Runtime.perform(%Domain{id: :main}, "update_cycle_time", %{"value" => "0"})

    assert {:error, dc_resource, %{level: "error", text: ":invalid_integer"}} =
             Runtime.perform(default_dc_resource(), "await_dc_locked", %{"value" => "-1"})

    assert dc_resource?(dc_resource)

    assert {:error, %Slave{name: :rack_1}, %{level: "error", text: ":invalid_transition"}} =
             Runtime.perform(%Slave{name: :rack_1}, "transition", %{"value" => "invalid"})

    assert {:error, %Master{}, %{level: "error", text: ":invalid_log_level"}} =
             Runtime.perform(%Master{}, "set_log_level", %{"value" => "verbose"})
  end

  defp default_dc_resource do
    cond do
      Code.ensure_loaded?(EtherCAT.DC.Status) and
          function_exported?(EtherCAT.DC.Status, :__struct__, 0) ->
        struct(EtherCAT.DC.Status)

      Code.ensure_loaded?(EtherCAT.DC) and function_exported?(EtherCAT.DC, :__struct__, 0) ->
        struct(EtherCAT.DC)

      true ->
        %{}
    end
  end

  defp dc_resource?(resource) do
    is_struct(resource, EtherCAT.DC.Status) or is_struct(resource, EtherCAT.DC)
  end
end
