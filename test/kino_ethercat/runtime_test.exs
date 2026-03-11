defmodule KinoEtherCAT.RuntimeTest do
  use ExUnit.Case, async: false

  alias EtherCAT.Bus.Link.SinglePort
  alias EtherCAT.Domain.Config, as: DomainConfig
  alias EtherCAT.{Bus, Domain, Master, Slave}
  alias KinoEtherCAT.{Runtime, StartConfig}

  setup_all do
    if is_nil(Process.whereis(StartConfig)) do
      start_supervised!(StartConfig)
    end

    :ok
  end

  setup do
    StartConfig.clear()
    :ok
  end

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
    assert %{
             kind: "master",
             meta_layout: "stacked",
             details_title: "Runtime",
             controls: %{
               title: "Actions",
               buttons: buttons,
               summary: control_summary,
               help: control_help
             },
             log_controls: log_controls
           } =
             Runtime.payload(%Master{})

    assert [%{id: "start", label: "Start session", disabled: true}] = buttons
    assert Enum.any?(control_summary, &(&1.label == "Remembered start" and &1.value == "missing"))
    assert Enum.any?(control_summary, &(&1.label == "Next step"))
    assert is_binary(control_help)
    assert log_controls.select.id == "set_log_level"
    assert log_controls.select.label == "Log filter"
    assert log_controls.select.value == "all"
    assert Enum.any?(log_controls.buttons, &(&1.id == "clear_logs"))

    assert %{kind: "slave", status: "unavailable", log_controls: slave_log_controls} =
             Runtime.payload(%Slave{name: :rack_1})

    assert slave_log_controls.select.value == "all"

    assert %{kind: "domain", status: "unavailable", log_controls: domain_log_controls} =
             Runtime.payload(%Domain{id: :main})

    assert domain_log_controls.select.value == "all"

    assert %{
             kind: "bus",
             controls: %{submit: %{id: "set_frame_timeout"}},
             log_controls: bus_log_controls
           } =
             Runtime.payload(struct(Bus))

    assert bus_log_controls.select.value == "all"

    assert %{
             kind: "dc",
             controls: %{submit: %{id: "await_dc_locked"}},
             log_controls: dc_log_controls
           } =
             Runtime.payload(default_dc_resource())

    assert dc_log_controls.select.value == "all"
  end

  test "master start button becomes available when a start config is remembered" do
    assert :ok = StartConfig.remember(interface: "eth0")

    assert %{controls: %{buttons: buttons}} = Runtime.payload(%Master{})
    assert [%{id: "start", label: "Start session", disabled: false}] = buttons
  end

  test "runtime start option reconstruction preserves UDP transport" do
    master = %Master{
      slave_configs: [],
      domain_configs: [%{id: :main, cycle_time_us: 1_000, miss_threshold: 10}],
      dc_config: nil,
      scan_poll_ms: 100,
      scan_stable_ms: 1_000,
      base_station: 0x1000
    }

    bus = %Bus{
      idx: 0,
      link: %SinglePort{
        open_opts: [transport: :udp, host: {127, 0, 0, 2}, port: 34_980]
      },
      link_mod: SinglePort
    }

    assert {:ok, opts} = Runtime.start_options_from_runtime(master, bus)
    assert opts[:transport] == :udp
    assert opts[:host] == {127, 0, 0, 2}
    assert opts[:port] == 34_980
    refute Keyword.has_key?(opts, :interface)
    assert [%DomainConfig{id: :main, cycle_time_us: 1_000, miss_threshold: 10}] = opts[:domains]
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
