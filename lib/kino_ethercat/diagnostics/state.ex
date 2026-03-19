defmodule KinoEtherCAT.Diagnostics.State do
  @moduledoc false

  @default_history_limit 40
  @default_event_limit 30
  @default_slice_ms 1_000

  @type telemetry_event :: [atom()]
  @type telemetry_measurements :: map()
  @type telemetry_metadata :: map()

  @spec new(keyword()) :: map()
  def new(opts \\ []) do
    history_limit = Keyword.get(opts, :history_limit, @default_history_limit)
    event_limit = Keyword.get(opts, :event_limit, @default_event_limit)
    slice_ms = Keyword.get(opts, :slice_ms, @default_slice_ms)

    %{
      history_limit: history_limit,
      event_limit: event_limit,
      slice_ms: slice_ms,
      snapshot: %{
        state: "idle",
        last_failure: nil,
        slaves: [],
        domains: [],
        dc: nil
      },
      master_metrics: new_master_metrics(),
      transactions: %{
        "realtime" => new_transaction_metrics(),
        "reliable" => new_transaction_metrics()
      },
      queues: %{
        "realtime" => new_queue_metrics(),
        "reliable" => new_queue_metrics()
      },
      bus: %{
        expired_realtime: 0,
        exceptions: 0,
        sent_frames: 0,
        sent_bytes: 0,
        received_frames: 0,
        received_bytes: 0,
        dropped_frames: 0,
        dropped_bytes: 0,
        rtt_ns_history: [],
        sent_slices: [],
        sent_byte_slices: [],
        received_slices: [],
        received_byte_slices: [],
        dropped_slices: [],
        dropped_byte_slices: [],
        expired_realtime_slices: [],
        exception_slices: [],
        rtt_ns_slices: [],
        dropped_reasons: %{},
        pending_tx: %{},
        links: %{}
      },
      dc_metrics: new_dc_metrics(),
      domain_metrics: %{},
      slave_events: %{},
      timeline: []
    }
  end

  @spec apply_poll_snapshot(map(), map()) :: map()
  def apply_poll_snapshot(state, snapshot) when is_map(snapshot) do
    domain_metrics =
      Enum.reduce(snapshot.domains, state.domain_metrics, fn domain, acc ->
        Map.put_new(acc, domain.id, new_domain_metrics())
      end)

    dc_metrics =
      case snapshot.dc do
        %{lock_state: lock_state} -> Map.put(state.dc_metrics, :lock_state, lock_state)
        _ -> state.dc_metrics
      end

    master_metrics =
      state.master_metrics
      |> Map.put(:public_state, snapshot.state || state.master_metrics.public_state)

    %{
      state
      | snapshot: snapshot,
        domain_metrics: domain_metrics,
        dc_metrics: dc_metrics,
        master_metrics: master_metrics
    }
  end

  @spec apply_telemetry(map(), telemetry_event(), telemetry_measurements(), telemetry_metadata()) ::
          map()
  def apply_telemetry(state, event, measurements, metadata)

  def apply_telemetry(state, [:ethercat, :bus, :transact, :stop], measurements, metadata) do
    class = class_key(metadata.class)
    duration_us = native_to_us(measurements.duration)

    update_in(state, [:transactions, class], fn metric ->
      metric
      |> append_history(:latency_history, duration_us, state.history_limit)
      |> append_sample_slice(:latency_slices, duration_us, state.history_limit, state.slice_ms)
      |> Map.update!(:count, &(&1 + 1))
      |> Map.put(:last_wkc, Map.get(metadata, :total_wkc))
      |> Map.update!(:datagrams, &(&1 + Map.get(metadata, :datagram_count, 0)))
      |> Map.put(:last_status, format_reason(Map.get(metadata, :status)))
      |> Map.put(:last_error_kind, format_reason(Map.get(metadata, :error_kind)))
    end)
  end

  def apply_telemetry(state, [:ethercat, :bus, :transact, :exception], _measurements, metadata) do
    state
    |> update_in([:bus, :exceptions], &(&1 + 1))
    |> update_count_series([:bus, :exception_slices], 1, state.history_limit, state.slice_ms)
    |> record_event("warn", "Bus exception", format_reason(metadata.reason))
  end

  def apply_telemetry(state, [:ethercat, :bus, :submission, :enqueued], measurements, metadata) do
    class = class_key(metadata.class)

    update_in(state, [:queues, class], fn metric ->
      metric
      |> append_history(:history, measurements.queue_depth, state.history_limit)
      |> append_sample_slice(
        :slices,
        measurements.queue_depth,
        state.history_limit,
        state.slice_ms
      )
      |> Map.put(:last_depth, measurements.queue_depth)
      |> Map.update!(:peak_depth, &max(&1, measurements.queue_depth))
      |> Map.put(:last_link, metadata.link)
    end)
  end

  def apply_telemetry(state, [:ethercat, :bus, :submission, :expired], measurements, metadata) do
    detail = "#{metadata.link} aged #{measurements.age_us} us"

    state
    |> update_in([:bus, :expired_realtime], &(&1 + 1))
    |> update_count_series(
      [:bus, :expired_realtime_slices],
      1,
      state.history_limit,
      state.slice_ms
    )
    |> record_event("warn", "Realtime submission expired", detail)
  end

  def apply_telemetry(state, [:ethercat, :bus, :dispatch, :sent], measurements, metadata) do
    class = class_key(metadata.class)

    update_in(state, [:transactions, class], fn metric ->
      metric
      |> Map.update!(:dispatches, &(&1 + 1))
      |> Map.update!(:transactions, &(&1 + measurements.transaction_count))
      |> Map.update!(:datagrams, &(&1 + measurements.datagram_count))
      |> Map.put(:last_link, metadata.link)
    end)
  end

  def apply_telemetry(state, [:ethercat, :bus, :frame, :sent], measurements, metadata) do
    size = Map.get(measurements, :size, 0)

    state
    |> update_in([:bus, :sent_frames], &(&1 + 1))
    |> update_in([:bus, :sent_bytes], &(&1 + size))
    |> update_count_series([:bus, :sent_slices], 1, state.history_limit, state.slice_ms)
    |> update_count_series([:bus, :sent_byte_slices], size, state.history_limit, state.slice_ms)
    |> update_link_traffic(metadata.link, metadata.endpoint, metadata.port, :sent, size)
    |> maybe_track_tx_timestamp(metadata.link, metadata.port, measurements.tx_timestamp)
  end

  def apply_telemetry(state, [:ethercat, :bus, :frame, :received], measurements, metadata) do
    size = Map.get(measurements, :size, 0)

    state
    |> update_in([:bus, :received_frames], &(&1 + 1))
    |> update_in([:bus, :received_bytes], &(&1 + size))
    |> update_count_series([:bus, :received_slices], 1, state.history_limit, state.slice_ms)
    |> update_count_series(
      [:bus, :received_byte_slices],
      size,
      state.history_limit,
      state.slice_ms
    )
    |> update_link_traffic(metadata.link, metadata.endpoint, metadata.port, :received, size)
    |> maybe_track_rtt(metadata.link, metadata.port, measurements.rx_timestamp)
  end

  def apply_telemetry(state, [:ethercat, :bus, :frame, :dropped], measurements, metadata) do
    size = Map.get(measurements, :size, 0)

    state
    |> update_in([:bus, :dropped_frames], &(&1 + 1))
    |> update_in([:bus, :dropped_bytes], &(&1 + size))
    |> update_count_series([:bus, :dropped_slices], 1, state.history_limit, state.slice_ms)
    |> update_count_series(
      [:bus, :dropped_byte_slices],
      size,
      state.history_limit,
      state.slice_ms
    )
    |> update_in([:bus, :dropped_reasons], fn reasons ->
      Map.update(reasons, to_string(metadata.reason), 1, &(&1 + 1))
    end)
    |> update_link_drop(metadata.link)
  end

  def apply_telemetry(state, [:ethercat, :bus, :link, :down], _measurements, metadata) do
    detail = "#{metadata.link}: #{metadata.endpoint} • #{format_reason(metadata.reason)}"

    state
    |> put_link(metadata.link, %{
      status: "down",
      reason: format_reason(metadata.reason),
      endpoint: metadata.endpoint
    })
    |> record_event("danger", "Link down", detail)
  end

  def apply_telemetry(state, [:ethercat, :bus, :link, :reconnected], _measurements, metadata) do
    detail = "#{metadata.link}: #{metadata.endpoint}"

    state
    |> put_link(metadata.link, %{status: "up", reason: nil, endpoint: metadata.endpoint})
    |> record_event("info", "Link reconnected", detail)
  end

  def apply_telemetry(state, [:ethercat, :dc, :tick], measurements, _metadata) do
    put_in(state, [:dc_metrics, :tick_wkc], measurements.wkc)
  end

  def apply_telemetry(state, [:ethercat, :dc, :sync_diff, :observed], measurements, _metadata) do
    state
    |> update_history(
      [:dc_metrics, :sync_diff_ns_history],
      measurements.max_sync_diff_ns,
      state.history_limit
    )
    |> update_sample_series(
      [:dc_metrics, :sync_diff_slices],
      measurements.max_sync_diff_ns,
      state.history_limit,
      state.slice_ms
    )
  end

  def apply_telemetry(state, [:ethercat, :dc, :lock, :changed], _measurements, metadata) do
    event = %{
      from: to_string(metadata.from),
      to: to_string(metadata.to),
      max_sync_diff_ns: metadata.max_sync_diff_ns,
      at_ms: now_ms()
    }

    state
    |> put_in([:dc_metrics, :lock_state], to_string(metadata.to))
    |> update_history([:dc_metrics, :lock_events], event, 10)
    |> record_event(
      lock_level(metadata.to),
      "DC lock #{metadata.from} -> #{metadata.to}",
      max_sync_diff(metadata.max_sync_diff_ns)
    )
  end

  def apply_telemetry(
        state,
        [:ethercat, :dc, :runtime, :state, :changed],
        _measurements,
        metadata
      ) do
    event = %{
      from: to_string(metadata.from),
      to: to_string(metadata.to),
      reason: format_reason(metadata.reason),
      consecutive_failures: metadata.consecutive_failures,
      at_ms: now_ms()
    }

    title =
      case metadata.to do
        :healthy -> "DC runtime healthy"
        :failing -> "DC runtime failing"
        _ -> "DC runtime changed"
      end

    detail =
      [event.reason, "failures #{event.consecutive_failures}"]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" • ")

    state
    |> put_in([:dc_metrics, :runtime_state], to_string(metadata.to))
    |> put_in([:dc_metrics, :runtime_reason], event.reason)
    |> put_in([:dc_metrics, :consecutive_failures], metadata.consecutive_failures)
    |> update_history([:dc_metrics, :runtime_events], event, 10)
    |> record_event(dc_runtime_level(metadata.to), title, detail)
  end

  def apply_telemetry(state, [:ethercat, :domain, :cycle, :done], measurements, metadata) do
    domain_id = to_string(metadata.domain)

    state
    |> ensure_domain_metrics(domain_id)
    |> update_history(
      [:domain_metrics, domain_id, :cycle_history],
      measurements.duration_us,
      state.history_limit
    )
    |> update_sample_series(
      [:domain_metrics, domain_id, :cycle_slices],
      measurements.duration_us,
      state.history_limit,
      state.slice_ms
    )
  end

  def apply_telemetry(state, [:ethercat, :domain, :cycle, :invalid], measurements, metadata) do
    domain_id = to_string(metadata.domain)
    previous = get_in(state, [:domain_metrics, domain_id, :last_invalid])

    event = %{
      reason: format_reason(metadata.reason),
      expected_wkc: Map.get(metadata, :expected_wkc),
      actual_wkc: Map.get(metadata, :actual_wkc),
      reply_count: Map.get(metadata, :reply_count),
      total_invalid_count: Map.get(measurements, :total_invalid_count),
      invalid_at_us: Map.get(measurements, :invalid_at_us),
      at_ms: now_ms()
    }

    state
    |> ensure_domain_metrics(domain_id)
    |> update_in([:domain_metrics, domain_id, :invalid_events], &(&1 + 1))
    |> update_count_series(
      [:domain_metrics, domain_id, :invalid_slices],
      1,
      state.history_limit,
      state.slice_ms
    )
    |> put_in([:domain_metrics, domain_id, :last_invalid], event)
    |> maybe_record_domain_event("warn", "Domain invalid", domain_id, previous, event)
  end

  def apply_telemetry(
        state,
        [:ethercat, :domain, :cycle, :transport_miss],
        measurements,
        metadata
      ) do
    domain_id = to_string(metadata.domain)
    previous = get_in(state, [:domain_metrics, domain_id, :last_transport_miss])

    event = %{
      reason: format_reason(metadata.reason),
      expected_wkc: Map.get(metadata, :expected_wkc),
      actual_wkc: Map.get(metadata, :actual_wkc),
      reply_count: Map.get(metadata, :reply_count),
      consecutive_miss_count: Map.get(measurements, :consecutive_miss_count),
      total_invalid_count: Map.get(measurements, :total_invalid_count),
      invalid_at_us: Map.get(measurements, :invalid_at_us),
      at_ms: now_ms()
    }

    state
    |> ensure_domain_metrics(domain_id)
    |> update_in([:domain_metrics, domain_id, :transport_miss_events], &(&1 + 1))
    |> update_count_series(
      [:domain_metrics, domain_id, :transport_miss_slices],
      1,
      state.history_limit,
      state.slice_ms
    )
    |> put_in([:domain_metrics, domain_id, :last_transport_miss], event)
    |> maybe_record_domain_event("danger", "Domain transport miss", domain_id, previous, event)
  end

  def apply_telemetry(state, [:ethercat, :domain, :stopped], _measurements, metadata) do
    domain_id = to_string(metadata.domain)
    detail = "#{domain_id}: #{format_reason(metadata.reason)}"

    state
    |> ensure_domain_metrics(domain_id)
    |> put_in([:domain_metrics, domain_id, :stop_reason], format_reason(metadata.reason))
    |> record_event("danger", "Domain stopped", detail)
  end

  def apply_telemetry(state, [:ethercat, :domain, :crashed], _measurements, metadata) do
    domain_id = to_string(metadata.domain)
    detail = "#{domain_id}: #{format_reason(metadata.reason)}"

    state
    |> ensure_domain_metrics(domain_id)
    |> put_in([:domain_metrics, domain_id, :crash_reason], format_reason(metadata.reason))
    |> record_event("danger", "Domain crashed", detail)
  end

  def apply_telemetry(state, [:ethercat, :master, :state, :changed], _measurements, metadata) do
    event =
      %{
        from: to_string(metadata.from),
        to: to_string(metadata.to),
        public_state: to_string(metadata.public_state),
        runtime_target: to_string(metadata.runtime_target),
        at_ms: now_ms()
      }
      |> Map.put(:cause, master_state_change_cause(state, metadata.to))

    detail = master_state_change_detail(event)

    state
    |> put_in([:snapshot, :state], event.public_state)
    |> put_in([:master_metrics, :public_state], event.public_state)
    |> put_in([:master_metrics, :runtime_target], event.runtime_target)
    |> update_history([:master_metrics, :state_changes], event, 12)
    |> record_event(
      master_state_level(metadata.to),
      master_state_change_title(event),
      detail
    )
  end

  def apply_telemetry(state, [:ethercat, :master, :startup, :bus_stable], measurements, _metadata) do
    detail = "#{measurements.slave_count} slave(s)"

    state
    |> put_in([:master_metrics, :startup_slave_count], measurements.slave_count)
    |> record_event("info", "Bus stable", detail)
  end

  def apply_telemetry(
        state,
        [:ethercat, :master, :configuration, :result],
        measurements,
        metadata
      ) do
    result = %{
      status: to_string(metadata.status),
      duration_ms: measurements.duration_ms,
      slave_count: metadata.slave_count,
      runtime_target: to_string(metadata.runtime_target),
      reason: format_reason(metadata.reason),
      at_ms: now_ms()
    }

    detail =
      [
        "#{result.slave_count} slave(s)",
        "#{result.duration_ms} ms",
        "target #{result.runtime_target}",
        result.reason
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" • ")

    state
    |> put_in([:master_metrics, :configuration_result], result)
    |> record_event(
      master_result_level(metadata.status),
      "Configuration #{result.status}",
      detail
    )
  end

  def apply_telemetry(state, [:ethercat, :master, :activation, :result], measurements, metadata) do
    result = %{
      status: to_string(metadata.status),
      duration_ms: measurements.duration_ms,
      runtime_target: to_string(metadata.runtime_target),
      blocked_count: metadata.blocked_count,
      reason: format_reason(metadata.reason),
      at_ms: now_ms()
    }

    detail =
      [
        "#{result.duration_ms} ms",
        "target #{result.runtime_target}",
        "blocked #{result.blocked_count}",
        result.reason
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" • ")

    state
    |> put_in([:master_metrics, :activation_result], result)
    |> record_event(master_result_level(metadata.status), "Activation #{result.status}", detail)
  end

  def apply_telemetry(state, [:ethercat, :master, :dc_lock, :decision], _measurements, metadata) do
    event = %{
      transition: to_string(metadata.transition),
      policy: to_string(metadata.policy),
      outcome: to_string(metadata.outcome),
      lock_state: to_string(metadata.lock_state),
      max_sync_diff_ns: metadata.max_sync_diff_ns,
      at_ms: now_ms()
    }

    detail =
      [
        "#{event.transition} • #{event.outcome}",
        "policy #{event.policy}",
        "lock #{event.lock_state}",
        max_sync_diff(metadata.max_sync_diff_ns)
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" • ")

    state
    |> update_history([:master_metrics, :dc_lock_decisions], event, 10)
    |> record_event(master_dc_lock_level(metadata.transition), "Master DC lock decision", detail)
  end

  def apply_telemetry(
        state,
        [:ethercat, :master, :slave_fault, :changed],
        _measurements,
        metadata
      ) do
    slave = to_string(metadata.slave)
    from_fault = format_reason(metadata.from)
    to_fault = format_reason(metadata.to)
    title = if is_nil(to_fault), do: "fault cleared", else: "fault changed"

    detail =
      [
        "#{from_fault || "none"} -> #{to_fault || "none"}",
        format_reason(metadata.to_detail)
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" • ")

    state
    |> put_slave_event(slave, %{
      level: slave_fault_level(metadata.to),
      title: title,
      detail: detail
    })
    |> record_event(slave_fault_level(metadata.to), "Slave fault #{slave}", detail)
  end

  def apply_telemetry(state, [:ethercat, :slave, :crashed], _measurements, metadata) do
    slave = to_string(metadata.slave)
    detail = "#{slave}: #{format_reason(metadata.reason)}"

    state
    |> put_slave_event(slave, %{
      level: "danger",
      title: "crashed",
      detail: format_reason(metadata.reason)
    })
    |> record_event("danger", "Slave crashed", detail)
  end

  def apply_telemetry(state, [:ethercat, :slave, :health, :fault], measurements, metadata) do
    slave = to_string(metadata.slave)

    detail =
      "#{slave} AL #{al_state_name(measurements.al_state)} error #{hex(measurements.error_code, 4)}"

    state
    |> put_slave_event(slave, %{level: "danger", title: "health fault", detail: detail})
    |> record_event("danger", "Slave fault", detail)
  end

  def apply_telemetry(state, [:ethercat, :slave, :down], _measurements, metadata) do
    slave = to_string(metadata.slave)
    detail = "#{slave} station #{hex(metadata.station, 4)} • #{format_reason(metadata.reason)}"

    state
    |> put_slave_event(slave, %{level: "warn", title: "down", detail: detail})
    |> record_event("warn", "Slave down", detail)
  end

  def apply_telemetry(state, [:ethercat, :slave, :startup, :retry], measurements, metadata) do
    slave = to_string(metadata.slave)

    detail =
      [
        "phase #{metadata.phase}",
        format_reason(metadata.reason),
        "retry #{measurements.retry_count}",
        "#{measurements.retry_delay_ms} ms"
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" • ")

    state
    |> put_slave_event(slave, %{level: "warn", title: "startup retry", detail: detail})
    |> record_event("warn", "Slave retry", "#{slave} • #{detail}")
  end

  def apply_telemetry(state, _event, _measurements, _metadata), do: state

  @spec payload(map()) :: map()
  def payload(state) do
    master = payload_master(state)

    %{
      state: master.public_state,
      last_failure: state.snapshot.last_failure,
      slice_ms: state.slice_ms,
      master: master,
      slaves: payload_slaves(state),
      domains: payload_domains(state),
      dc: payload_dc(state),
      bus: payload_bus(state),
      timeline: state.timeline
    }
  end

  defp payload_master(state) do
    %{
      public_state: state.master_metrics.public_state || state.snapshot.state || "idle",
      runtime_target: state.master_metrics.runtime_target,
      startup_slave_count: state.master_metrics.startup_slave_count,
      configuration_result: state.master_metrics.configuration_result,
      activation_result: state.master_metrics.activation_result,
      state_changes: Enum.reverse(state.master_metrics.state_changes),
      dc_lock_decisions: Enum.reverse(state.master_metrics.dc_lock_decisions)
    }
  end

  defp payload_slaves(state) do
    snapshot_names = MapSet.new(Enum.map(state.snapshot.slaves, & &1.name))

    current =
      Enum.map(state.snapshot.slaves, fn slave ->
        Map.put(slave, :last_event, Map.get(state.slave_events, slave.name))
      end)

    orphaned =
      state.slave_events
      |> Enum.reject(fn {name, _event} -> MapSet.member?(snapshot_names, name) end)
      |> Enum.map(fn {name, event} ->
        %{
          name: name,
          station: nil,
          al_state: "unknown",
          al_error: nil,
          fault: nil,
          configuration_error: nil,
          last_event: event
        }
      end)

    current ++ orphaned
  end

  defp payload_domains(state) do
    current_ids = MapSet.new(Enum.map(state.snapshot.domains, & &1.id))

    current =
      Enum.map(state.snapshot.domains, fn domain ->
        metric = Map.get(state.domain_metrics, domain.id, new_domain_metrics())

        Map.merge(domain, %{
          cycle_history: metric.cycle_history,
          last_cycle_us: List.last(metric.cycle_history),
          avg_cycle_us: average(metric.cycle_history),
          cycle_slices:
            payload_sample_slices(metric.cycle_slices, state.history_limit, state.slice_ms),
          invalid_slices:
            payload_count_slices(metric.invalid_slices, state.history_limit, state.slice_ms),
          transport_miss_slices:
            payload_count_slices(
              metric.transport_miss_slices,
              state.history_limit,
              state.slice_ms
            ),
          invalid_events: metric.invalid_events,
          transport_miss_events: metric.transport_miss_events,
          last_invalid: metric.last_invalid,
          last_transport_miss: metric.last_transport_miss,
          stop_reason: metric.stop_reason,
          crash_reason: metric.crash_reason
        })
      end)

    orphaned =
      state.domain_metrics
      |> Enum.reject(fn {id, _metric} -> MapSet.member?(current_ids, id) end)
      |> Enum.map(fn {id, metric} ->
        %{
          id: id,
          cycle_time_us: nil,
          state: "unknown",
          cycle_health: "unknown",
          cycle_count: 0,
          miss_count: 0,
          total_miss_count: 0,
          expected_wkc: 0,
          logical_base: nil,
          image_size: nil,
          last_invalid_cycle_at_us: nil,
          last_invalid_reason: nil,
          cycle_history: metric.cycle_history,
          last_cycle_us: List.last(metric.cycle_history),
          avg_cycle_us: average(metric.cycle_history),
          cycle_slices:
            payload_sample_slices(metric.cycle_slices, state.history_limit, state.slice_ms),
          invalid_slices:
            payload_count_slices(metric.invalid_slices, state.history_limit, state.slice_ms),
          transport_miss_slices:
            payload_count_slices(
              metric.transport_miss_slices,
              state.history_limit,
              state.slice_ms
            ),
          invalid_events: metric.invalid_events,
          transport_miss_events: metric.transport_miss_events,
          last_invalid: metric.last_invalid,
          last_transport_miss: metric.last_transport_miss,
          stop_reason: metric.stop_reason,
          crash_reason: metric.crash_reason
        }
      end)

    current ++ orphaned
  end

  defp payload_dc(state) do
    base = state.snapshot.dc || %{}

    Map.merge(
      %{
        configured: false,
        active: false,
        lock_state: state.dc_metrics.lock_state || "disabled",
        reference_clock: nil,
        reference_station: nil,
        max_sync_diff_ns: nil,
        cycle_ns: nil,
        monitor_failures: 0,
        await_lock: nil,
        lock_policy: nil
      },
      base
    )
    |> Map.merge(%{
      lock_state: Map.get(base, :lock_state) || state.dc_metrics.lock_state || "disabled",
      tick_wkc: state.dc_metrics.tick_wkc,
      sync_diff_history: state.dc_metrics.sync_diff_ns_history,
      sync_diff_slices:
        payload_sample_slices(
          state.dc_metrics.sync_diff_slices,
          state.history_limit,
          state.slice_ms
        ),
      lock_events: Enum.reverse(state.dc_metrics.lock_events),
      runtime_state: state.dc_metrics.runtime_state || "healthy",
      runtime_reason: state.dc_metrics.runtime_reason,
      consecutive_failures: state.dc_metrics.consecutive_failures,
      runtime_events: Enum.reverse(state.dc_metrics.runtime_events)
    })
  end

  defp payload_bus(state) do
    %{
      expired_realtime: state.bus.expired_realtime,
      exceptions: state.bus.exceptions,
      transactions: %{
        realtime: payload_transaction_metrics(state.transactions["realtime"], state),
        reliable: payload_transaction_metrics(state.transactions["reliable"], state)
      },
      queues: %{
        realtime: payload_queue_metrics(state.queues["realtime"], state),
        reliable: payload_queue_metrics(state.queues["reliable"], state)
      },
      frames: %{
        sent: state.bus.sent_frames,
        sent_bytes: state.bus.sent_bytes,
        received: state.bus.received_frames,
        received_bytes: state.bus.received_bytes,
        dropped: state.bus.dropped_frames,
        dropped_bytes: state.bus.dropped_bytes,
        last_rtt_ns: List.last(state.bus.rtt_ns_history),
        peak_rtt_ns: Enum.max(state.bus.rtt_ns_history, fn -> nil end),
        rtt_history: state.bus.rtt_ns_history,
        rtt_slices:
          payload_sample_slices(state.bus.rtt_ns_slices, state.history_limit, state.slice_ms),
        sent_slices:
          payload_count_slices(state.bus.sent_slices, state.history_limit, state.slice_ms),
        sent_bandwidth_slices:
          payload_rate_slices(state.bus.sent_byte_slices, state.history_limit, state.slice_ms),
        received_slices:
          payload_count_slices(state.bus.received_slices, state.history_limit, state.slice_ms),
        received_bandwidth_slices:
          payload_rate_slices(state.bus.received_byte_slices, state.history_limit, state.slice_ms),
        dropped_slices:
          payload_count_slices(state.bus.dropped_slices, state.history_limit, state.slice_ms),
        dropped_bandwidth_slices:
          payload_rate_slices(state.bus.dropped_byte_slices, state.history_limit, state.slice_ms),
        expired_slices:
          payload_count_slices(
            state.bus.expired_realtime_slices,
            state.history_limit,
            state.slice_ms
          ),
        exception_slices:
          payload_count_slices(state.bus.exception_slices, state.history_limit, state.slice_ms),
        dropped_reasons: payload_dropped_reasons(state.bus.dropped_reasons)
      },
      links: payload_links(state.bus.links)
    }
  end

  defp payload_transaction_metrics(metric, state) do
    Map.merge(metric, %{
      last_latency_us: List.last(metric.latency_history),
      avg_latency_us: average(metric.latency_history),
      latency_slices:
        payload_sample_slices(metric.latency_slices, state.history_limit, state.slice_ms)
    })
  end

  defp payload_queue_metrics(metric, state) do
    Map.merge(metric, %{
      avg_depth: average(metric.history),
      slices: payload_sample_slices(metric.slices, state.history_limit, state.slice_ms)
    })
  end

  defp payload_dropped_reasons(reasons) do
    reasons
    |> Enum.map(fn {reason, count} -> %{reason: reason, count: count} end)
    |> Enum.sort_by(&{-&1.count, &1.reason})
  end

  defp payload_links(links) do
    links
    |> Enum.map(fn {name, info} ->
      %{
        name: name,
        endpoint: info.endpoint,
        status: info.status,
        reason: info.reason,
        at_ms: info.at_ms,
        sent: info.sent,
        received: info.received,
        sent_bytes: info.sent_bytes,
        received_bytes: info.received_bytes,
        dropped: info.dropped,
        ports:
          info.ports
          |> Enum.map(fn {port, port_info} ->
            Map.put(port_info, :port, port)
          end)
          |> Enum.sort_by(&port_order(&1.port))
      }
    end)
    |> Enum.sort_by(& &1.name)
  end

  defp new_master_metrics do
    %{
      public_state: "idle",
      runtime_target: nil,
      state_changes: [],
      startup_slave_count: nil,
      configuration_result: nil,
      activation_result: nil,
      dc_lock_decisions: []
    }
  end

  defp new_transaction_metrics do
    %{
      latency_history: [],
      latency_slices: [],
      count: 0,
      dispatches: 0,
      transactions: 0,
      datagrams: 0,
      last_wkc: nil,
      last_status: nil,
      last_error_kind: nil,
      last_link: nil
    }
  end

  defp new_queue_metrics do
    %{history: [], slices: [], peak_depth: 0, last_depth: 0, last_link: nil}
  end

  defp new_dc_metrics do
    %{
      tick_wkc: nil,
      sync_diff_ns_history: [],
      sync_diff_slices: [],
      lock_state: nil,
      lock_events: [],
      runtime_state: nil,
      runtime_reason: nil,
      consecutive_failures: 0,
      runtime_events: []
    }
  end

  defp new_domain_metrics do
    %{
      cycle_history: [],
      cycle_slices: [],
      invalid_slices: [],
      transport_miss_slices: [],
      invalid_events: 0,
      transport_miss_events: 0,
      last_invalid: nil,
      last_transport_miss: nil,
      stop_reason: nil,
      crash_reason: nil
    }
  end

  defp new_link_info(endpoint) do
    %{
      endpoint: endpoint,
      status: "up",
      reason: nil,
      at_ms: now_ms(),
      sent: 0,
      received: 0,
      sent_bytes: 0,
      received_bytes: 0,
      dropped: 0,
      ports: %{}
    }
  end

  defp new_link_port_info do
    %{sent: 0, received: 0, sent_bytes: 0, received_bytes: 0}
  end

  defp put_link(state, link, attrs) do
    info =
      state.bus.links
      |> Map.get(link, new_link_info(Map.get(attrs, :endpoint)))
      |> Map.merge(attrs)
      |> Map.put(:at_ms, now_ms())

    put_in(state, [:bus, :links, link], info)
  end

  defp update_link_traffic(state, link, endpoint, port, direction, size) do
    update_in(state, [:bus, :links], fn links ->
      link_info =
        links
        |> Map.get(link, new_link_info(endpoint))
        |> Map.put(:endpoint, endpoint)
        |> Map.put(:status, "up")
        |> Map.put(:reason, nil)
        |> Map.put(:at_ms, now_ms())
        |> increment_link_counter(direction, size)
        |> update_in([:ports, to_string(port)], fn port_info ->
          port_info
          |> Kernel.||(new_link_port_info())
          |> increment_port_counter(direction, size)
        end)

      Map.put(links, link, link_info)
    end)
  end

  defp update_link_drop(state, nil), do: state

  defp update_link_drop(state, link) do
    update_in(state, [:bus, :links], fn links ->
      link_info =
        links
        |> Map.get(link, new_link_info(nil))
        |> Map.update!(:dropped, &(&1 + 1))
        |> Map.put(:at_ms, now_ms())

      Map.put(links, link, link_info)
    end)
  end

  defp increment_link_counter(link_info, :sent, size) do
    link_info
    |> Map.update!(:sent, &(&1 + 1))
    |> Map.update!(:sent_bytes, &(&1 + size))
  end

  defp increment_link_counter(link_info, :received, size) do
    link_info
    |> Map.update!(:received, &(&1 + 1))
    |> Map.update!(:received_bytes, &(&1 + size))
  end

  defp increment_port_counter(port_info, :sent, size) do
    port_info
    |> Map.update!(:sent, &(&1 + 1))
    |> Map.update!(:sent_bytes, &(&1 + size))
  end

  defp increment_port_counter(port_info, :received, size) do
    port_info
    |> Map.update!(:received, &(&1 + 1))
    |> Map.update!(:received_bytes, &(&1 + size))
  end

  defp put_slave_event(state, slave, event) do
    put_in(state, [:slave_events, slave], Map.put(event, :at_ms, now_ms()))
  end

  defp maybe_track_tx_timestamp(state, _link, _port, nil), do: state

  defp maybe_track_tx_timestamp(state, link, port, tx_timestamp) do
    update_in(state, [:bus, :pending_tx, {link, port}], fn queue ->
      queue = queue || []
      Enum.take(queue ++ [tx_timestamp], -10)
    end)
  end

  defp maybe_track_rtt(state, _link, _port, nil), do: state

  defp maybe_track_rtt(state, link, port, rx_timestamp) do
    case get_in(state, [:bus, :pending_tx, {link, port}]) do
      [tx_timestamp | rest] when is_integer(tx_timestamp) and rx_timestamp >= tx_timestamp ->
        rtt_ns = System.convert_time_unit(rx_timestamp - tx_timestamp, :native, :nanosecond)

        state
        |> put_in([:bus, :pending_tx, {link, port}], rest)
        |> update_history([:bus, :rtt_ns_history], rtt_ns, state.history_limit)
        |> update_sample_series(
          [:bus, :rtt_ns_slices],
          rtt_ns,
          state.history_limit,
          state.slice_ms
        )

      [_ | rest] ->
        put_in(state, [:bus, :pending_tx, {link, port}], rest)

      _ ->
        state
    end
  end

  defp ensure_domain_metrics(state, domain_id) do
    update_in(state, [:domain_metrics], &Map.put_new(&1, domain_id, new_domain_metrics()))
  end

  defp maybe_record_domain_event(state, level, title, domain_id, previous, current) do
    if should_record_domain_event?(previous, current) do
      record_event(state, level, title, "#{domain_id} • #{format_domain_detail(current)}")
    else
      state
    end
  end

  defp should_record_domain_event?(nil, _current), do: true

  defp should_record_domain_event?(previous, current) do
    previous.reason != current.reason or previous.actual_wkc != current.actual_wkc or
      previous.reply_count != current.reply_count
  end

  defp format_domain_detail(event) do
    [
      event.reason,
      wkc_detail(event.actual_wkc, event.expected_wkc),
      reply_detail(event.reply_count),
      miss_detail(Map.get(event, :consecutive_miss_count)),
      invalid_detail(event.total_invalid_count)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" • ")
  end

  defp wkc_detail(nil, nil), do: nil
  defp wkc_detail(actual, expected), do: "WKC #{actual || "?"}/#{expected || "?"}"

  defp reply_detail(nil), do: nil
  defp reply_detail(reply_count), do: "replies #{reply_count}"

  defp miss_detail(nil), do: nil
  defp miss_detail(count), do: "misses #{count}"

  defp invalid_detail(nil), do: nil
  defp invalid_detail(count), do: "invalid #{count}"

  defp class_key(class) when is_atom(class), do: Atom.to_string(class)
  defp class_key(class) when is_binary(class), do: class
  defp class_key(class), do: to_string(class)

  defp record_event(state, level, title, detail) do
    event = %{
      id: System.unique_integer([:positive, :monotonic]),
      at_ms: now_ms(),
      level: level,
      title: title,
      detail: detail
    }

    update_in(state, [:timeline], fn timeline ->
      [event | timeline] |> Enum.take(state.event_limit)
    end)
  end

  defp master_state_change_title(%{from: state, to: state}), do: "Master stayed #{state}"

  defp master_state_change_title(%{from: "recovering", to: "operational"}),
    do: "Master recovered to operational"

  defp master_state_change_title(%{to: state}), do: "Master entered #{state}"

  defp master_state_change_detail(event) do
    [
      "#{event.from} -> #{event.to}",
      runtime_target_detail(event.runtime_target),
      cause_detail(event.cause)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" • ")
  end

  defp runtime_target_detail(nil), do: nil
  defp runtime_target_detail(""), do: nil
  defp runtime_target_detail(runtime_target), do: "target #{runtime_target}"

  defp cause_detail(nil), do: nil
  defp cause_detail(cause), do: "cause #{cause}"

  defp master_state_change_cause(state, to) when to in [:recovering, :activation_blocked] do
    change_at_ms = now_ms()

    state.timeline
    |> Enum.find_value(fn event -> relevant_master_state_cause(event, change_at_ms) end)
  end

  defp master_state_change_cause(_state, _to), do: nil

  defp relevant_master_state_cause(%{at_ms: at_ms}, change_at_ms)
       when is_integer(at_ms) and change_at_ms - at_ms > 2_000,
       do: nil

  defp relevant_master_state_cause(%{title: title, detail: detail}, _change_at_ms) do
    cond do
      title in [
        "Domain invalid",
        "Domain stopped",
        "Domain crashed",
        "DC runtime failing",
        "Master DC lock decision",
        "Link down",
        "Bus exception",
        "Realtime submission expired",
        "Slave down",
        "Slave crashed",
        "Slave fault"
      ] ->
        state_change_cause_detail(title, detail)

      String.starts_with?(title, "Slave fault ") ->
        state_change_cause_detail(title, detail)

      true ->
        nil
    end
  end

  defp relevant_master_state_cause(_event, _change_at_ms), do: nil

  defp state_change_cause_detail(title, detail) when detail in [nil, ""], do: title

  defp state_change_cause_detail(title, detail) do
    "#{title}: #{detail}"
  end

  defp lock_level(:locked), do: "info"
  defp lock_level(_other), do: "warn"

  defp dc_runtime_level(:healthy), do: "info"
  defp dc_runtime_level(:failing), do: "warn"
  defp dc_runtime_level(_other), do: "warn"

  defp master_state_level(:operational), do: "info"
  defp master_state_level(:recovering), do: "warn"
  defp master_state_level(:activation_blocked), do: "warn"
  defp master_state_level(:idle), do: "info"
  defp master_state_level(_other), do: "info"

  defp master_result_level(:ok), do: "info"
  defp master_result_level(:blocked), do: "warn"
  defp master_result_level(:error), do: "danger"
  defp master_result_level(_other), do: "warn"

  defp master_dc_lock_level(:regained), do: "info"
  defp master_dc_lock_level(:lost), do: "warn"
  defp master_dc_lock_level(_other), do: "warn"

  defp slave_fault_level(nil), do: "info"
  defp slave_fault_level(_other), do: "warn"

  defp update_history(state, path, value, limit) do
    update_in(state, path, fn history ->
      history = history || []
      Enum.take(history ++ [value], -limit)
    end)
  end

  defp append_history(metric, key, value, limit) when is_map(metric) do
    Map.update!(metric, key, fn history ->
      Enum.take(history ++ [value], -limit)
    end)
  end

  defp append_sample_slice(metric, key, value, limit, slice_ms) when is_map(metric) do
    Map.update!(metric, key, fn slices ->
      put_sample_slice(slices, value, limit, slice_ms)
    end)
  end

  defp update_sample_series(state, path, value, limit, slice_ms) do
    update_in(state, path, fn slices ->
      put_sample_slice(slices || [], value, limit, slice_ms)
    end)
  end

  defp update_count_series(state, path, increment, limit, slice_ms) do
    update_in(state, path, fn slices ->
      put_count_slice(slices || [], increment, limit, slice_ms)
    end)
  end

  defp put_sample_slice(slices, value, limit, slice_ms) do
    bucket_at = bucket_start(now_ms(), slice_ms)

    case slices do
      [%{at_ms: ^bucket_at} = slice | rest] ->
        [merge_sample_slice(slice, value) | rest]

      _ ->
        [
          %{
            at_ms: bucket_at,
            count: 1,
            sum: value,
            avg: value,
            max: value,
            min: value,
            last: value
          }
          | slices
        ]
        |> Enum.take(limit)
    end
  end

  defp put_count_slice(slices, increment, limit, slice_ms) do
    bucket_at = bucket_start(now_ms(), slice_ms)

    case slices do
      [%{at_ms: ^bucket_at} = slice | rest] ->
        [%{slice | count: slice.count + increment} | rest]

      _ ->
        [%{at_ms: bucket_at, count: increment} | slices]
        |> Enum.take(limit)
    end
  end

  defp merge_sample_slice(slice, value) do
    count = slice.count + 1
    sum = slice.sum + value

    %{
      slice
      | count: count,
        sum: sum,
        avg: Float.round(sum / count, 1),
        max: max(slice.max, value),
        min: min(slice.min, value),
        last: value
    }
  end

  defp payload_sample_slices(slices, limit, slice_ms) do
    slices
    |> fill_slice_window(limit, slice_ms, %{count: 0, avg: 0, max: 0, min: 0, last: 0})
    |> Enum.map(fn slice ->
      %{
        at_ms: slice.at_ms,
        label: slice_label(slice.at_ms),
        value: slice.avg,
        peak: slice.max,
        count: slice.count
      }
    end)
  end

  defp payload_count_slices(slices, limit, slice_ms) do
    slices
    |> fill_slice_window(limit, slice_ms, %{count: 0})
    |> Enum.map(fn slice ->
      %{
        at_ms: slice.at_ms,
        label: slice_label(slice.at_ms),
        value: slice.count
      }
    end)
  end

  defp payload_rate_slices(slices, limit, slice_ms) do
    scale = if slice_ms > 0, do: 1_000 / slice_ms, else: 1

    slices
    |> fill_slice_window(limit, slice_ms, %{count: 0})
    |> Enum.map(fn slice ->
      %{
        at_ms: slice.at_ms,
        label: slice_label(slice.at_ms),
        value: Float.round(slice.count * scale, 1)
      }
    end)
  end

  defp fill_slice_window(slices, limit, slice_ms, defaults) do
    latest_at = bucket_start(now_ms(), slice_ms)

    by_bucket =
      Map.new(slices, fn slice ->
        {slice.at_ms, slice}
      end)

    for offset <- Enum.reverse(0..(limit - 1)) do
      at_ms = latest_at - offset * slice_ms

      %{at_ms: at_ms}
      |> Map.merge(defaults)
      |> Map.merge(Map.get(by_bucket, at_ms, %{}))
    end
  end

  defp native_to_us(duration) when is_integer(duration) do
    System.convert_time_unit(duration, :native, :microsecond)
  end

  defp average([]), do: nil

  defp average(values) do
    values
    |> Enum.sum()
    |> Kernel./(length(values))
    |> Float.round(1)
  end

  defp format_reason(nil), do: nil
  defp format_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)

  defp al_state_name(1), do: "INIT"
  defp al_state_name(2), do: "PREOP"
  defp al_state_name(4), do: "SAFEOP"
  defp al_state_name(8), do: "OP"
  defp al_state_name(other), do: inspect(other)

  defp max_sync_diff(nil), do: nil
  defp max_sync_diff(value), do: "#{value} ns"

  defp port_order("primary"), do: 0
  defp port_order("secondary"), do: 1
  defp port_order(other), do: other

  defp bucket_start(at_ms, slice_ms), do: div(at_ms, slice_ms) * slice_ms

  defp slice_label(at_ms) do
    at_ms
    |> DateTime.from_unix!(:millisecond)
    |> Calendar.strftime("%H:%M:%S")
  end

  defp hex(nil, _pad), do: "n/a"
  defp hex(value, pad), do: "0x" <> String.pad_leading(Integer.to_string(value, 16), pad, "0")

  defp now_ms, do: System.system_time(:millisecond)
end
