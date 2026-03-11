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

  test "should_auto_scan? only enables auto scan for a brand-new empty cell" do
    assert Setup.should_auto_scan?(%{}, %{slaves: []})

    refute Setup.should_auto_scan?(%{"transport" => "udp"}, %{slaves: []})
    refute Setup.should_auto_scan?(%{}, %{slaves: [%{"name" => "inputs"}]})
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
    assert Setup.discovered_name(:slave_1, 0x1001, %{0x1001 => "inputs"}) == "inputs"
    assert Setup.discovered_name(:slave_2, 0x1002, %{0x1001 => "inputs"}) == "slave_2"
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
