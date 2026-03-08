defmodule KinoEtherCAT.DiagnosticsStateTest do
  use ExUnit.Case, async: true

  alias KinoEtherCAT.Diagnostics.State

  test "records realtime transaction latency and queue depth history" do
    state =
      State.new(history_limit: 5)
      |> State.apply_poll_snapshot(%{
        phase: "operational",
        last_failure: nil,
        slaves: [],
        domains: [],
        dc: nil
      })
      |> State.apply_telemetry(
        [:ethercat, :bus, :submission, :enqueued],
        %{queue_depth: 3},
        %{class: :realtime, link: "eth0", state: :awaiting}
      )
      |> State.apply_telemetry(
        [:ethercat, :bus, :transact, :stop],
        %{duration: System.convert_time_unit(240, :microsecond, :native)},
        %{class: :realtime, total_wkc: 7, datagram_count: 2}
      )

    payload = State.payload(state)

    assert payload.phase == "operational"
    assert payload.slice_ms == 1_000
    assert payload.bus.queues.realtime.peak_depth == 3
    assert_in_delta List.last(payload.bus.queues.realtime.slices).value, 3.0, 0.1
    assert payload.bus.transactions.realtime.last_latency_us == 240
    assert_in_delta List.last(payload.bus.transactions.realtime.latency_slices).value, 240.0, 0.1
    assert payload.bus.transactions.realtime.last_wkc == 7
  end

  test "accepts transaction stop telemetry without total_wkc" do
    state =
      State.new(history_limit: 5)
      |> State.apply_telemetry(
        [:ethercat, :bus, :transact, :stop],
        %{duration: System.convert_time_unit(125, :microsecond, :native)},
        %{class: :realtime, datagram_count: 1}
      )

    payload = State.payload(state)

    assert payload.bus.transactions.realtime.last_latency_us == 125
    assert payload.bus.transactions.realtime.last_wkc == nil
    assert payload.bus.transactions.realtime.datagrams == 1
  end

  test "builds slice payloads for DC and domain telemetry" do
    state =
      State.new(history_limit: 4)
      |> State.apply_telemetry(
        [:ethercat, :dc, :sync_diff, :observed],
        %{max_sync_diff_ns: 140},
        %{ref_station: 4096}
      )
      |> State.apply_telemetry(
        [:ethercat, :domain, :cycle, :done],
        %{duration_us: 900, cycle_count: 1},
        %{domain: :main}
      )
      |> State.apply_telemetry(
        [:ethercat, :domain, :cycle, :missed],
        %{miss_count: 1},
        %{domain: :main, reason: :deadline}
      )

    payload = State.payload(state)
    [domain] = payload.domains

    assert_in_delta List.last(payload.dc.sync_diff_slices).value, 140.0, 0.1
    assert domain.id == "main"
    assert_in_delta List.last(domain.cycle_slices).value, 900.0, 0.1
    assert List.last(domain.miss_slices).value == 1
    assert domain.last_miss_reason == "deadline"
  end

  test "records link and slave fault events into the timeline" do
    state =
      State.new(event_limit: 5)
      |> State.apply_telemetry(
        [:ethercat, :bus, :link, :down],
        %{},
        %{link: "eth0", reason: :timeout}
      )
      |> State.apply_telemetry(
        [:ethercat, :slave, :health, :fault],
        %{al_state: 8, error_code: 16},
        %{slave: :rack, station: 0x1001}
      )

    payload = State.payload(state)

    assert [%{name: "eth0", status: "down"}] = payload.bus.links
    assert [%{title: "Slave fault"} | _] = payload.timeline
    assert [%{name: "rack", last_event: %{title: "fault"}}] = payload.slaves
  end
end
