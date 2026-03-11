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
end
