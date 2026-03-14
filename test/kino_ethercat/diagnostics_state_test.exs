defmodule KinoEtherCAT.DiagnosticsStateTest do
  use ExUnit.Case, async: true

  alias KinoEtherCAT.Diagnostics.State

  test "records realtime transaction latency and queue depth history" do
    state =
      State.new(history_limit: 5)
      |> State.apply_poll_snapshot(%{
        state: "operational",
        last_failure: nil,
        slaves: [],
        domains: [],
        dc: nil
      })
      |> State.apply_telemetry(
        [:ethercat, :bus, :submission, :enqueued],
        %{queue_depth: 3},
        %{class: :realtime, link: "uplink", state: :awaiting}
      )
      |> State.apply_telemetry(
        [:ethercat, :bus, :transact, :stop],
        %{duration: System.convert_time_unit(240, :microsecond, :native)},
        %{class: :realtime, total_wkc: 7, datagram_count: 2, status: :ok}
      )

    payload = State.payload(state)

    assert payload.state == "operational"
    assert payload.slice_ms == 1_000
    assert payload.bus.queues.realtime.peak_depth == 3
    assert_in_delta List.last(payload.bus.queues.realtime.slices).value, 3.0, 0.1
    assert payload.bus.transactions.realtime.last_latency_us == 240
    assert_in_delta List.last(payload.bus.transactions.realtime.latency_slices).value, 240.0, 0.1
    assert payload.bus.transactions.realtime.last_wkc == 7
    assert payload.bus.transactions.realtime.last_status == "ok"
  end

  test "tracks master lifecycle and dc runtime telemetry" do
    state =
      State.new(history_limit: 4)
      |> State.apply_telemetry(
        [:ethercat, :master, :state, :changed],
        %{},
        %{from: :preop_ready, to: :operational, public_state: :operational, runtime_target: :op}
      )
      |> State.apply_telemetry(
        [:ethercat, :master, :startup, :bus_stable],
        %{slave_count: 3},
        %{}
      )
      |> State.apply_telemetry(
        [:ethercat, :master, :configuration, :result],
        %{duration_ms: 210},
        %{status: :ok, slave_count: 3, runtime_target: :op, reason: nil}
      )
      |> State.apply_telemetry(
        [:ethercat, :master, :activation, :result],
        %{duration_ms: 45},
        %{status: :ok, runtime_target: :op, blocked_count: 0, reason: nil}
      )
      |> State.apply_telemetry(
        [:ethercat, :dc, :runtime, :state, :changed],
        %{},
        %{from: :healthy, to: :failing, reason: :lost_lock, consecutive_failures: 2}
      )

    payload = State.payload(state)

    assert payload.state == "operational"
    assert payload.master.runtime_target == "op"
    assert payload.master.startup_slave_count == 3
    assert payload.master.configuration_result.status == "ok"
    assert payload.master.activation_result.status == "ok"
    assert payload.dc.runtime_state == "failing"
    assert payload.dc.runtime_reason == "lost_lock"
    assert payload.dc.consecutive_failures == 2
  end

  test "builds cycle, invalid, and transport miss slices for domains" do
    state =
      State.new(history_limit: 4)
      |> State.apply_poll_snapshot(%{
        state: "recovering",
        last_failure: nil,
        slaves: [],
        domains: [
          %{
            id: "main",
            cycle_time_us: 1_000,
            state: "cycling",
            cycle_health: "healthy",
            cycle_count: 1,
            miss_count: 0,
            total_miss_count: 0,
            expected_wkc: 3,
            logical_base: 4096,
            image_size: 64,
            last_invalid_cycle_at_us: nil,
            last_invalid_reason: nil
          }
        ],
        dc: nil
      })
      |> State.apply_telemetry(
        [:ethercat, :domain, :cycle, :done],
        %{duration_us: 900, cycle_count: 1, completed_at_us: 1_000},
        %{domain: :main}
      )
      |> State.apply_telemetry(
        [:ethercat, :domain, :cycle, :invalid],
        %{total_invalid_count: 1, invalid_at_us: 2_000},
        %{domain: :main, reason: :wkc_mismatch, expected_wkc: 3, actual_wkc: 2, reply_count: 1}
      )
      |> State.apply_telemetry(
        [:ethercat, :domain, :cycle, :transport_miss],
        %{consecutive_miss_count: 2, total_invalid_count: 2, invalid_at_us: 3_000},
        %{domain: :main, reason: :timeout, expected_wkc: 3, actual_wkc: 0, reply_count: 0}
      )

    payload = State.payload(state)
    [domain] = payload.domains

    assert_in_delta List.last(domain.cycle_slices).value, 900.0, 0.1
    assert List.last(domain.invalid_slices).value == 1
    assert List.last(domain.transport_miss_slices).value == 1
    assert domain.invalid_events == 1
    assert domain.transport_miss_events == 1
    assert domain.last_invalid.reason == "wkc_mismatch"
    assert domain.last_transport_miss.reason == "timeout"
    assert domain.last_transport_miss.consecutive_miss_count == 2
  end

  test "records link activity and slave retry events" do
    state =
      State.new(event_limit: 5)
      |> State.apply_telemetry(
        [:ethercat, :bus, :frame, :sent],
        %{size: 128, tx_timestamp: nil},
        %{link: "bus0", endpoint: "veth-s0", port: :primary}
      )
      |> State.apply_telemetry(
        [:ethercat, :bus, :frame, :received],
        %{size: 96, rx_timestamp: nil},
        %{link: "bus0", endpoint: "veth-s0", port: :secondary}
      )
      |> State.apply_telemetry(
        [:ethercat, :bus, :link, :down],
        %{},
        %{link: "bus0", endpoint: "veth-s0", reason: :timeout}
      )
      |> State.apply_telemetry(
        [:ethercat, :slave, :startup, :retry],
        %{retry_count: 2, retry_delay_ms: 100},
        %{slave: :rack, station: 0x1001, phase: :preop, reason: :timeout}
      )

    payload = State.payload(state)

    assert [%{name: "bus0", endpoint: "veth-s0", status: "down", ports: ports}] =
             payload.bus.links

    assert Enum.any?(ports, &(&1.port == "primary" and &1.sent == 1))
    assert Enum.any?(ports, &(&1.port == "secondary" and &1.received == 1))
    assert [%{title: "Slave retry"} | _] = payload.timeline
    assert [%{name: "rack", last_event: %{title: "startup retry"}}] = payload.slaves
  end

  test "tracks payload throughput from frame sizes" do
    state =
      State.new(history_limit: 4)
      |> State.apply_telemetry(
        [:ethercat, :bus, :frame, :sent],
        %{size: 128, tx_timestamp: nil},
        %{link: "eth0", endpoint: "sim", port: :primary}
      )
      |> State.apply_telemetry(
        [:ethercat, :bus, :frame, :received],
        %{size: 96, rx_timestamp: nil},
        %{link: "eth0", endpoint: "sim", port: :primary}
      )
      |> State.apply_telemetry(
        [:ethercat, :bus, :frame, :dropped],
        %{size: 32},
        %{link: "eth0", reason: :idx_mismatch}
      )

    payload = State.payload(state)

    assert payload.bus.frames.sent_bytes == 128
    assert payload.bus.frames.received_bytes == 96
    assert payload.bus.frames.dropped_bytes == 32
    assert List.last(payload.bus.frames.sent_bandwidth_slices).value == 128.0
    assert List.last(payload.bus.frames.received_bandwidth_slices).value == 96.0
    assert List.last(payload.bus.frames.dropped_bandwidth_slices).value == 32.0
  end
end
