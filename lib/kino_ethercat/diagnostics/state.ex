defmodule KinoEtherCAT.DiagnosticsState do
  @moduledoc false

  @default_history_limit 40
  @default_event_limit 30

  @type telemetry_event :: [atom()]
  @type telemetry_measurements :: map()
  @type telemetry_metadata :: map()

  @spec new(keyword()) :: map()
  def new(opts \\ []) do
    history_limit = Keyword.get(opts, :history_limit, @default_history_limit)
    event_limit = Keyword.get(opts, :event_limit, @default_event_limit)

    %{
      history_limit: history_limit,
      event_limit: event_limit,
      snapshot: %{
        phase: "idle",
        last_failure: nil,
        slaves: [],
        domains: [],
        dc: nil
      },
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
        received_frames: 0,
        dropped_frames: 0,
        ignored_frames: 0,
        rtt_ns_history: [],
        dropped_reasons: %{},
        pending_tx: %{},
        links: %{}
      },
      dc_metrics: %{
        tick_wkc: nil,
        sync_diff_ns_history: [],
        lock_state: nil,
        lock_events: []
      },
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

    %{state | snapshot: snapshot, domain_metrics: domain_metrics, dc_metrics: dc_metrics}
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
      |> Map.update!(:count, &(&1 + 1))
      |> Map.put(:last_wkc, metadata.total_wkc)
    end)
  end

  def apply_telemetry(state, [:ethercat, :bus, :transact, :exception], _measurements, metadata) do
    state
    |> update_in([:bus, :exceptions], &(&1 + 1))
    |> record_event("warn", "Bus exception", format_reason(metadata.reason))
  end

  def apply_telemetry(state, [:ethercat, :bus, :submission, :enqueued], measurements, metadata) do
    class = class_key(metadata.class)

    update_in(state, [:queues, class], fn metric ->
      metric
      |> append_history(:history, measurements.queue_depth, state.history_limit)
      |> Map.put(:last_depth, measurements.queue_depth)
      |> Map.update!(:peak_depth, &max(&1, measurements.queue_depth))
    end)
  end

  def apply_telemetry(state, [:ethercat, :bus, :submission, :expired], measurements, metadata) do
    detail = "#{metadata.link} aged #{measurements.age_us} us"

    state
    |> update_in([:bus, :expired_realtime], &(&1 + 1))
    |> record_event("warn", "Realtime submission expired", detail)
  end

  def apply_telemetry(state, [:ethercat, :bus, :dispatch, :sent], measurements, metadata) do
    class = class_key(metadata.class)

    update_in(state, [:transactions, class], fn metric ->
      metric
      |> Map.update!(:dispatches, &(&1 + 1))
      |> Map.update!(:transactions, &(&1 + measurements.transaction_count))
      |> Map.update!(:datagrams, &(&1 + measurements.datagram_count))
    end)
  end

  def apply_telemetry(state, [:ethercat, :bus, :frame, :sent], measurements, metadata) do
    state
    |> update_in([:bus, :sent_frames], &(&1 + 1))
    |> maybe_track_tx_timestamp(metadata.link, metadata.port, measurements.tx_timestamp)
  end

  def apply_telemetry(state, [:ethercat, :bus, :frame, :received], measurements, metadata) do
    state
    |> update_in([:bus, :received_frames], &(&1 + 1))
    |> maybe_track_rtt(metadata.link, metadata.port, measurements.rx_timestamp)
  end

  def apply_telemetry(state, [:ethercat, :bus, :frame, :dropped], _measurements, metadata) do
    state
    |> update_in([:bus, :dropped_frames], &(&1 + 1))
    |> update_in([:bus, :dropped_reasons], fn reasons ->
      Map.update(reasons, to_string(metadata.reason), 1, fn count -> count + 1 end)
    end)
  end

  def apply_telemetry(state, [:ethercat, :bus, :frame, :ignored], _measurements, _metadata) do
    update_in(state, [:bus, :ignored_frames], &(&1 + 1))
  end

  def apply_telemetry(state, [:ethercat, :bus, :link, :down], _measurements, metadata) do
    detail = "#{metadata.link}: #{format_reason(metadata.reason)}"

    state
    |> put_link(metadata.link, %{status: "down", reason: format_reason(metadata.reason)})
    |> record_event("danger", "Link down", detail)
  end

  def apply_telemetry(state, [:ethercat, :bus, :link, :reconnected], _measurements, metadata) do
    state
    |> put_link(metadata.link, %{status: "up", reason: nil})
    |> record_event("info", "Link reconnected", metadata.link)
  end

  def apply_telemetry(state, [:ethercat, :dc, :tick], measurements, _metadata) do
    put_in(state, [:dc_metrics, :tick_wkc], measurements.wkc)
  end

  def apply_telemetry(state, [:ethercat, :dc, :sync_diff, :observed], measurements, _metadata) do
    update_history(
      state,
      [:dc_metrics, :sync_diff_ns_history],
      measurements.max_sync_diff_ns,
      state.history_limit
    )
  end

  def apply_telemetry(state, [:ethercat, :dc, :lock, :changed], _measurements, metadata) do
    event = %{
      from: to_string(metadata.from),
      to: to_string(metadata.to),
      max_sync_diff_ns: metadata.max_sync_diff_ns
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

  def apply_telemetry(state, [:ethercat, :domain, :cycle, :done], measurements, metadata) do
    domain_id = to_string(metadata.domain)

    state
    |> ensure_domain_metrics(domain_id)
    |> update_history(
      [:domain_metrics, domain_id, :cycle_history],
      measurements.duration_us,
      state.history_limit
    )
  end

  def apply_telemetry(state, [:ethercat, :domain, :cycle, :missed], measurements, metadata) do
    domain_id = to_string(metadata.domain)

    state
    |> ensure_domain_metrics(domain_id)
    |> update_in([:domain_metrics, domain_id, :missed_events], &(&1 + 1))
    |> put_in([:domain_metrics, domain_id, :last_miss_reason], format_reason(metadata.reason))
    |> put_in([:domain_metrics, domain_id, :last_miss_count], measurements.miss_count)
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
    |> put_slave_event(slave, %{level: "danger", title: "fault", detail: detail})
    |> record_event("danger", "Slave fault", detail)
  end

  def apply_telemetry(state, [:ethercat, :slave, :down], _measurements, metadata) do
    slave = to_string(metadata.slave)
    detail = "#{slave} station #{hex(metadata.station, 4)}"

    state
    |> put_slave_event(slave, %{level: "warn", title: "down", detail: detail})
    |> record_event("warn", "Slave down", detail)
  end

  def apply_telemetry(state, _event, _measurements, _metadata), do: state

  @spec payload(map()) :: map()
  def payload(state) do
    %{
      phase: state.snapshot.phase,
      last_failure: state.snapshot.last_failure,
      slaves: payload_slaves(state),
      domains: payload_domains(state),
      dc: payload_dc(state),
      bus: payload_bus(state),
      timeline: state.timeline
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
          missed_events: metric.missed_events,
          last_miss_reason: metric.last_miss_reason,
          last_miss_count: metric.last_miss_count,
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
          cycle_count: 0,
          miss_count: 0,
          total_miss_count: 0,
          expected_wkc: 0,
          cycle_history: metric.cycle_history,
          last_cycle_us: List.last(metric.cycle_history),
          avg_cycle_us: average(metric.cycle_history),
          missed_events: metric.missed_events,
          last_miss_reason: metric.last_miss_reason,
          last_miss_count: metric.last_miss_count,
          stop_reason: metric.stop_reason,
          crash_reason: metric.crash_reason
        }
      end)

    current ++ orphaned
  end

  defp payload_dc(state) do
    base = state.snapshot.dc || %{}

    case map_size(base) do
      0 ->
        %{
          configured: false,
          active: false,
          lock_state: state.dc_metrics.lock_state || "disabled",
          reference_clock: nil,
          max_sync_diff_ns: nil,
          cycle_ns: nil,
          monitor_failures: 0,
          tick_wkc: state.dc_metrics.tick_wkc,
          sync_diff_history: state.dc_metrics.sync_diff_ns_history,
          lock_events: state.dc_metrics.lock_events
        }

      _ ->
        Map.merge(base, %{
          lock_state: base.lock_state || state.dc_metrics.lock_state || "unknown",
          tick_wkc: state.dc_metrics.tick_wkc,
          sync_diff_history: state.dc_metrics.sync_diff_ns_history,
          lock_events: state.dc_metrics.lock_events
        })
    end
  end

  defp payload_bus(state) do
    %{
      expired_realtime: state.bus.expired_realtime,
      exceptions: state.bus.exceptions,
      transactions: %{
        realtime: payload_transaction_metrics(state.transactions["realtime"]),
        reliable: payload_transaction_metrics(state.transactions["reliable"])
      },
      queues: %{
        realtime: state.queues["realtime"],
        reliable: state.queues["reliable"]
      },
      frames: %{
        sent: state.bus.sent_frames,
        received: state.bus.received_frames,
        dropped: state.bus.dropped_frames,
        ignored: state.bus.ignored_frames,
        last_rtt_ns: List.last(state.bus.rtt_ns_history),
        peak_rtt_ns: Enum.max(state.bus.rtt_ns_history, fn -> nil end),
        rtt_history: state.bus.rtt_ns_history,
        dropped_reasons: payload_dropped_reasons(state.bus.dropped_reasons)
      },
      links: payload_links(state.bus.links)
    }
  end

  defp payload_transaction_metrics(metric) do
    Map.merge(metric, %{
      last_latency_us: List.last(metric.latency_history),
      avg_latency_us: average(metric.latency_history)
    })
  end

  defp payload_dropped_reasons(reasons) do
    reasons
    |> Enum.map(fn {reason, count} -> %{reason: reason, count: count} end)
    |> Enum.sort_by(&{-&1.count, &1.reason})
  end

  defp payload_links(links) do
    links
    |> Enum.map(fn {name, info} -> Map.put(info, :name, name) end)
    |> Enum.sort_by(& &1.name)
  end

  defp new_transaction_metrics do
    %{
      latency_history: [],
      count: 0,
      dispatches: 0,
      transactions: 0,
      datagrams: 0,
      last_wkc: nil
    }
  end

  defp new_queue_metrics do
    %{history: [], peak_depth: 0, last_depth: 0}
  end

  defp new_domain_metrics do
    %{
      cycle_history: [],
      missed_events: 0,
      last_miss_reason: nil,
      last_miss_count: nil,
      stop_reason: nil,
      crash_reason: nil
    }
  end

  defp put_link(state, link, attrs) do
    info =
      state.bus.links
      |> Map.get(link, %{status: "unknown", reason: nil, at_ms: nil})
      |> Map.merge(attrs)
      |> Map.put(:at_ms, now_ms())

    put_in(state, [:bus, :links, link], info)
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

      [_ | rest] ->
        put_in(state, [:bus, :pending_tx, {link, port}], rest)

      _ ->
        state
    end
  end

  defp ensure_domain_metrics(state, domain_id) do
    update_in(state, [:domain_metrics], &Map.put_new(&1, domain_id, new_domain_metrics()))
  end

  defp class_key(class) when is_atom(class), do: Atom.to_string(class)
  defp class_key(class) when is_binary(class), do: class

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

  defp lock_level(:locked), do: "info"
  defp lock_level(_other), do: "warn"

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
  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)

  defp al_state_name(1), do: "INIT"
  defp al_state_name(2), do: "PREOP"
  defp al_state_name(4), do: "SAFEOP"
  defp al_state_name(8), do: "OP"
  defp al_state_name(other), do: inspect(other)

  defp max_sync_diff(nil), do: "sync diff unavailable"
  defp max_sync_diff(value), do: "#{value} ns"

  defp hex(nil, _pad), do: "n/a"
  defp hex(value, pad), do: "0x" <> String.pad_leading(Integer.to_string(value, 16), pad, "0")

  defp now_ms, do: System.system_time(:millisecond)
end
