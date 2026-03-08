defmodule KinoEtherCAT.DiagnosticsStateTest do
  use ExUnit.Case, async: true

  alias KinoEtherCAT.DiagnosticsState

  test "records realtime transaction latency and queue depth history" do
    state =
      DiagnosticsState.new(history_limit: 5)
      |> DiagnosticsState.apply_poll_snapshot(%{
        phase: "operational",
        last_failure: nil,
        slaves: [],
        domains: [],
        dc: nil
      })
      |> DiagnosticsState.apply_telemetry(
        [:ethercat, :bus, :submission, :enqueued],
        %{queue_depth: 3},
        %{class: :realtime, link: "eth0", state: :awaiting}
      )
      |> DiagnosticsState.apply_telemetry(
        [:ethercat, :bus, :transact, :stop],
        %{duration: System.convert_time_unit(240, :microsecond, :native)},
        %{class: :realtime, total_wkc: 7, datagram_count: 2}
      )

    payload = DiagnosticsState.payload(state)

    assert payload.phase == "operational"
    assert payload.bus.queues.realtime.peak_depth == 3
    assert payload.bus.transactions.realtime.last_latency_us == 240
    assert payload.bus.transactions.realtime.last_wkc == 7
  end

  test "accepts transaction stop telemetry without total_wkc" do
    state =
      DiagnosticsState.new(history_limit: 5)
      |> DiagnosticsState.apply_telemetry(
        [:ethercat, :bus, :transact, :stop],
        %{duration: System.convert_time_unit(125, :microsecond, :native)},
        %{class: :realtime, datagram_count: 1}
      )

    payload = DiagnosticsState.payload(state)

    assert payload.bus.transactions.realtime.last_latency_us == 125
    assert payload.bus.transactions.realtime.last_wkc == nil
    assert payload.bus.transactions.realtime.datagrams == 1
  end

  test "records link and slave fault events into the timeline" do
    state =
      DiagnosticsState.new(event_limit: 5)
      |> DiagnosticsState.apply_telemetry(
        [:ethercat, :bus, :link, :down],
        %{},
        %{link: "eth0", reason: :timeout}
      )
      |> DiagnosticsState.apply_telemetry(
        [:ethercat, :slave, :health, :fault],
        %{al_state: 8, error_code: 16},
        %{slave: :rack, station: 0x1001}
      )

    payload = DiagnosticsState.payload(state)

    assert [%{name: "eth0", status: "down"}] = payload.bus.links
    assert [%{title: "Slave fault"} | _] = payload.timeline
    assert [%{name: "rack", last_event: %{title: "fault"}}] = payload.slaves
  end
end
