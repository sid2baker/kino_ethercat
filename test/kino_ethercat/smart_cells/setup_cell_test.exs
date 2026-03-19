defmodule KinoEtherCAT.SmartCells.SetupCellTest do
  use ExUnit.Case, async: true

  alias KinoEtherCAT.SmartCells.Setup

  test "scan_start_opts adds a conservative discovery timeout budget" do
    opts =
      Setup.scan_start_opts(
        transport: :udp,
        host: {127, 0, 0, 2},
        port: 34_980,
        bind_ip: {127, 0, 0, 1}
      )

    assert Keyword.fetch!(opts, :frame_timeout_ms) == 25
    assert Keyword.fetch!(opts, :scan_stable_ms) == 250
    assert Keyword.fetch!(opts, :scan_poll_ms) == 100
    assert Keyword.fetch!(opts, :host) == {127, 0, 0, 2}
  end

  test "retryable_scan_reason? treats transient timeout failures as retryable" do
    assert Setup.retryable_scan_reason?(:timeout)
    assert Setup.retryable_scan_reason?(:awaiting_preop_timeout)
    assert Setup.retryable_scan_reason?({:configuration_failed, :timeout})
    assert Setup.retryable_scan_reason?({:station_assign_failed, 0, 4096, :timeout})

    refute Setup.retryable_scan_reason?(:missing_interface)
    refute Setup.retryable_scan_reason?({:configuration_failed, :missing_interface})
  end

  test "should_auto_scan? stays disabled so setup only scans on explicit user action" do
    refute Setup.should_auto_scan?(%{}, %{slaves: []}, fn -> false end)
    refute Setup.should_auto_scan?(%{}, %{slaves: []}, fn -> true end)
    refute Setup.should_auto_scan?(%{"transport" => "udp"}, %{slaves: []}, fn -> true end)
    refute Setup.should_auto_scan?(%{}, %{slaves: [%{"name" => "inputs"}]}, fn -> true end)
  end

  test "config_locked? reflects whether the setup config is safe to edit" do
    refute Setup.config_locked?(%{status: :idle, master_state: :idle, master_pid: nil})

    refute Setup.config_locked?(%{
             status: :discovered,
             master_state: :not_started,
             master_pid: nil
           })

    refute Setup.config_locked?(%{status: :discovered, master_state: :idle, master_pid: self()})

    assert Setup.config_locked?(%{status: :scanning, master_state: :idle, master_pid: nil})
    assert Setup.config_locked?(%{status: :canceling, master_state: :idle, master_pid: nil})

    assert Setup.config_locked?(%{
             status: :discovered,
             master_state: :preop_ready,
             master_pid: nil
           })
  end

  test "stopped_status keeps discovery results after cancelling a scan" do
    assert Setup.stopped_status(%{slaves: []}) == :idle
    assert Setup.stopped_status(%{slaves: [%{"name" => "inputs"}]}) == :discovered
  end

  test "discovered_slave_entry inherits simulator/runtime names on first discovery" do
    domains = [%{"id" => "main"}]

    assert %{
             "name" => "inputs",
             "discovered_name" => "inputs",
             "driver" => "KinoEtherCAT.Driver.EL1809"
           } =
             Setup.discovered_slave_entry(
               %{},
               "inputs",
               0x1001,
               %{vendor_id: 0x2, product_code: 0x0711_1389},
               "KinoEtherCAT.Driver.EL1809",
               domains,
               "main"
             )
  end

  test "discovered_name prefers simulator names by station when available" do
    simulator_name_index = %{by_station: %{0x1001 => "inputs"}, ordered: ["coupler", "inputs"]}

    assert Setup.discovered_name(:slave_1, 0x1001, 1, simulator_name_index) == "inputs"
    assert Setup.discovered_name(:slave_2, 0x1002, 1, simulator_name_index) == "inputs"
  end

  test "discovered_name falls back to simulator order before generated names" do
    simulator_name_index = %{by_station: %{}, ordered: ["coupler", "inputs", "outputs"]}

    assert Setup.discovered_name(:slave_1, 0x1001, 1, simulator_name_index) == "inputs"
    assert Setup.discovered_name(:slave_2, 0x1002, 2, simulator_name_index) == "outputs"
    assert Setup.discovered_name(:slave_3, 0x1003, 4, simulator_name_index) == "slave_3"
  end

  test "discovered_slave_entry preserves user-edited names on rescan" do
    domains = [%{"id" => "main"}]

    assert %{
             "name" => "left_inputs",
             "discovered_name" => "inputs",
             "driver" => "KinoEtherCAT.Driver.EL1809",
             "domain_id" => "main"
           } =
             Setup.discovered_slave_entry(
               %{
                 "name" => "left_inputs",
                 "discovered_name" => "inputs",
                 "driver" => "",
                 "domain_id" => "main"
               },
               "inputs",
               0x1001,
               %{vendor_id: 0x2, product_code: 0x0711_1389},
               "KinoEtherCAT.Driver.EL1809",
               domains,
               "main"
             )
  end
end
