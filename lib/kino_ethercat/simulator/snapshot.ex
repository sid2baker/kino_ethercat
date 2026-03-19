defmodule KinoEtherCAT.Simulator.Snapshot do
  @moduledoc false

  alias EtherCAT.Simulator
  alias EtherCAT.Simulator.Fault
  alias EtherCAT.Simulator.Transport.Raw.Fault, as: RawFault
  alias EtherCAT.Simulator.Transport.Udp.Fault, as: UdpFault

  @spec payload(map() | nil) :: map()
  def payload(message \\ nil) do
    case Simulator.info() do
      {:ok, info} ->
        running_payload(info, message)

      {:error, reason} ->
        offline_payload(reason, offline_message(reason, message))
    end
  end

  defp running_payload(info, message) do
    slaves = Map.get(info, :slaves, [])
    connections = Map.get(info, :connections, [])
    subscriptions = Map.get(info, :subscriptions, [])
    runtime_faults = runtime_faults_payload(info)
    transport_faults = transport_faults_payload(info)

    %{
      title: "EtherCAT Simulator",
      kind: "virtual ring",
      status: "running",
      message: message,
      summary:
        transport_summary(info) ++
          [
            %{label: "Slaves", value: Integer.to_string(length(slaves))},
            %{label: "Connections", value: Integer.to_string(length(connections))},
            %{label: "Subscriptions", value: Integer.to_string(length(subscriptions))},
            %{label: "Runtime faults", value: Integer.to_string(runtime_faults.active_count)}
          ] ++ maybe_transport_fault_summary(transport_faults),
      runtime_faults: runtime_faults,
      transport_faults: transport_faults,
      udp_faults: legacy_udp_faults_payload(transport_faults),
      slave_options: Enum.map(slaves, &Atom.to_string(&1.name)),
      slaves: Enum.map(slaves, &slave_payload/1),
      connections: Enum.map(connections, &connection_payload/1),
      subscriptions: Enum.map(subscriptions, &subscription_payload/1)
    }
  end

  defp offline_payload(reason, message) do
    runtime_faults = offline_runtime_faults()
    transport_faults = offline_transport_faults()

    %{
      title: "EtherCAT Simulator",
      kind: "virtual ring",
      status: "offline",
      reason: to_string(reason),
      message: message,
      summary: [
        %{label: "Transport", value: "offline"},
        %{label: "Slaves", value: "0"},
        %{label: "Connections", value: "0"},
        %{label: "Subscriptions", value: "0"},
        %{label: "Runtime faults", value: "0"}
      ],
      runtime_faults: runtime_faults,
      transport_faults: transport_faults,
      udp_faults: legacy_udp_faults_payload(transport_faults),
      slave_options: [],
      slaves: [],
      connections: [],
      subscriptions: []
    }
  end

  defp runtime_faults_payload(info) do
    drop_responses? = Map.get(info, :drop_responses?, false)
    wkc_offset = Map.get(info, :wkc_offset, 0)

    disconnected =
      info
      |> Map.get(:disconnected, [])
      |> Enum.map(&Atom.to_string/1)
      |> Enum.sort()

    command_offsets = command_offset_payloads(Map.get(info, :command_wkc_offsets, %{}))
    logical_offsets = logical_offset_payloads(Map.get(info, :logical_wkc_offsets, %{}))

    sticky_labels =
      [
        if(drop_responses?, do: "Drop responses"),
        if(wkc_offset != 0, do: "WKC offset #{wkc_offset}"),
        Enum.map(command_offsets, & &1.label),
        Enum.map(logical_offsets, & &1.label),
        if(disconnected != [], do: "Disconnected: #{Enum.join(disconnected, ", ")}")
      ]
      |> List.flatten()
      |> Enum.reject(&is_nil/1)

    next_label = runtime_wrapper_label(Map.get(info, :next_fault))
    next_count = if(is_binary(next_label), do: 1, else: 0)
    pending_faults = Map.get(info, :pending_faults, [])
    pending_labels = Enum.map(pending_faults, &Fault.describe/1)
    scheduled_faults = scheduled_fault_payloads(Map.get(info, :scheduled_faults, []))

    sticky_count =
      if(drop_responses?, do: 1, else: 0) +
        if(wkc_offset != 0, do: 1, else: 0) +
        length(command_offsets) +
        length(logical_offsets) +
        length(disconnected)

    %{
      drop_responses: drop_responses?,
      wkc_offset: wkc_offset,
      command_offsets: command_offsets,
      logical_offsets: logical_offsets,
      disconnected: disconnected,
      sticky_labels: sticky_labels,
      sticky_count: sticky_count,
      next_label: next_label,
      pending_labels: pending_labels,
      pending_count: length(pending_labels),
      scheduled_faults: scheduled_faults,
      scheduled_count: length(scheduled_faults),
      active_count: sticky_count + next_count + length(pending_labels) + length(scheduled_faults),
      summary:
        runtime_fault_summary(
          sticky_labels,
          length(pending_labels),
          length(scheduled_faults),
          next_label
        )
    }
  end

  defp offline_runtime_faults do
    %{
      drop_responses: false,
      wkc_offset: 0,
      command_offsets: [],
      logical_offsets: [],
      disconnected: [],
      sticky_labels: [],
      sticky_count: 0,
      next_label: nil,
      pending_labels: [],
      pending_count: 0,
      scheduled_faults: [],
      scheduled_count: 0,
      active_count: 0,
      summary: "No runtime faults."
    }
  end

  defp transport_faults_payload(info) do
    cond do
      raw_transport_running?(info) ->
        raw_transport_faults_payload(Map.fetch!(info, :raw))

      udp_transport_running?(info) ->
        udp_transport_faults_payload(Map.fetch!(info, :udp))

      true ->
        offline_transport_faults()
    end
  end

  defp udp_transport_faults_payload(%{} = udp) do
    pending_faults = Map.get(udp, :pending_faults, [])

    %{
      enabled: true,
      transport: "udp",
      title: "UDP reply faults",
      endpoint: udp_label(udp),
      last_response_captured: Map.get(udp, :last_response_captured?, false),
      next_label: udp_wrapper_label(Map.get(udp, :next_fault)),
      pending_labels: Enum.map(pending_faults, &UdpFault.describe/1),
      endpoints: [],
      mode: nil,
      active_count: length(pending_faults),
      summary: udp_fault_summary(pending_faults, Map.get(udp, :next_fault))
    }
  end

  defp raw_transport_faults_payload(%{} = raw) do
    mode = Map.get(raw, :mode, :single)
    endpoints = raw_endpoint_payloads(raw)

    active_endpoints =
      Enum.filter(endpoints, fn endpoint ->
        endpoint.response_delay_ms > 0
      end)

    %{
      enabled: true,
      transport: "raw",
      title: "Raw transport faults",
      endpoint: nil,
      last_response_captured: false,
      next_label: nil,
      pending_labels: [],
      endpoints: endpoints,
      mode: Atom.to_string(mode),
      active_count: length(active_endpoints),
      summary: raw_fault_summary(active_endpoints, mode)
    }
  end

  defp offline_transport_faults do
    %{
      enabled: false,
      transport: "disabled",
      title: "Transport faults",
      endpoint: "disabled",
      last_response_captured: false,
      next_label: nil,
      pending_labels: [],
      endpoints: [],
      mode: nil,
      active_count: 0,
      summary: "Transport fault injection unavailable."
    }
  end

  defp legacy_udp_faults_payload(%{transport: "udp"} = transport_faults), do: transport_faults
  defp legacy_udp_faults_payload(_transport_faults), do: offline_transport_faults()

  defp maybe_transport_fault_summary(%{enabled: true, active_count: active_count}) do
    [%{label: "Transport faults", value: Integer.to_string(active_count)}]
  end

  defp maybe_transport_fault_summary(_transport_faults), do: []

  defp transport_summary(info) do
    udp = Map.get(info, :udp)
    raw = Map.get(info, :raw)
    topology = Map.get(info, :topology)

    cond do
      is_map(raw) and map_size(raw) > 0 ->
        raw_transport_rows(raw) ++ topology_rows(topology)

      is_map(udp) ->
        [%{label: "UDP", value: udp_label(udp)}] ++ topology_rows(topology)

      true ->
        [%{label: "Transport", value: "disabled"}]
    end
  end

  defp raw_transport_rows(%{mode: _mode} = raw) do
    raw
    |> Map.delete(:mode)
    |> Enum.sort_by(fn {name, _} -> name end)
    |> Enum.map(fn {name, endpoint_info} ->
      interface = Map.get(endpoint_info, :interface, "active")
      %{label: "Raw (#{name})", value: to_string(interface)}
    end)
  end

  defp raw_transport_running?(info) do
    case Map.get(info, :raw) do
      raw when is_map(raw) -> map_size(raw) > 0
      _other -> false
    end
  end

  defp udp_transport_running?(info), do: is_map(Map.get(info, :udp))

  defp raw_endpoint_payloads(raw) do
    raw
    |> Map.delete(:mode)
    |> Enum.sort_by(fn {endpoint, _info} -> endpoint end)
    |> Enum.map(fn {endpoint, endpoint_info} ->
      response_delay_ms = Map.get(endpoint_info, :response_delay_ms, 0)
      from_ingress = Map.get(endpoint_info, :response_delay_from_ingress, :all)

      %{
        key: Atom.to_string(endpoint),
        endpoint: Atom.to_string(endpoint),
        interface: to_string(Map.get(endpoint_info, :interface, "active")),
        response_delay_ms: response_delay_ms,
        response_delay_from_ingress: Atom.to_string(from_ingress),
        active: response_delay_ms > 0,
        label: RawFault.describe({:delay_response, endpoint, response_delay_ms, from_ingress})
      }
    end)
  end

  defp topology_rows(%{mode: :redundant, break_after: break_after}) do
    value = if break_after, do: "redundant (break after #{break_after})", else: "redundant"
    [%{label: "Topology", value: value}]
  end

  defp topology_rows(%{mode: :linear}), do: [%{label: "Topology", value: "linear"}]
  defp topology_rows(_topology), do: []

  defp slave_payload(slave) do
    values = Map.get(slave, :values, %{})
    signals = Map.get(slave, :signals, %{})

    %{
      key: Atom.to_string(slave.name),
      name: Atom.to_string(slave.name),
      profile: to_string(Map.get(slave, :profile, :unknown)),
      state: to_string(Map.get(slave, :state, :unknown)),
      station: hex(Map.get(slave, :station, 0)),
      al_error: if(Map.get(slave, :al_error?, false), do: "latched", else: "clear"),
      al_status_code: hex(Map.get(slave, :al_status_code, 0)),
      dc: yes_no(Map.get(slave, :dc_capable?, false)),
      signals: map_size(signals),
      values: preview_values(values)
    }
  end

  defp connection_payload(%{
         source: {source_slave, source_signal},
         target: {target_slave, target_signal}
       }) do
    %{
      key: "#{source_slave}.#{source_signal}->#{target_slave}.#{target_signal}",
      source: "#{source_slave}.#{source_signal}",
      target: "#{target_slave}.#{target_signal}"
    }
  end

  defp subscription_payload(%{slave: slave, signal: signal, pid: pid}) do
    %{
      key: "#{slave}:#{signal}:#{inspect(pid)}",
      slave: Atom.to_string(slave),
      signal: to_string(signal),
      pid: inspect(pid)
    }
  end

  defp preview_values(values) when map_size(values) == 0, do: "none"

  defp preview_values(values) do
    entries =
      values
      |> Enum.sort_by(fn {name, _value} -> Atom.to_string(name) end)
      |> Enum.take(4)
      |> Enum.map_join(", ", fn {name, value} ->
        "#{name}=#{format_value(value)}"
      end)

    hidden = map_size(values) - min(map_size(values), 4)

    if hidden > 0 do
      "#{entries} (+#{hidden})"
    else
      entries
    end
  end

  defp runtime_fault_summary([], 0, 0, nil), do: "No runtime faults."

  defp runtime_fault_summary(sticky_labels, pending_count, scheduled_count, next_label) do
    queued_count = pending_count + if(is_binary(next_label), do: 1, else: 0)

    []
    |> maybe_prepend(sticky_labels != [], Enum.join(sticky_labels, " | "))
    |> maybe_prepend(
      queued_count > 0,
      "#{queued_count} queued exchange fault(s)" <>
        if(is_binary(next_label), do: " (next: #{next_label})", else: "")
    )
    |> maybe_prepend(scheduled_count > 0, "#{scheduled_count} scheduled runtime fault(s)")
    |> Enum.reverse()
    |> Enum.join(" | ")
  end

  defp udp_fault_summary([], _next_fault), do: "No queued UDP reply faults."

  defp udp_fault_summary(pending_faults, next_fault) do
    next_label = udp_wrapper_label(next_fault)

    "#{length(pending_faults)} queued UDP reply fault(s)" <>
      if(is_binary(next_label), do: " (next: #{next_label})", else: "")
  end

  defp runtime_wrapper_label({:next_exchange, fault}), do: Fault.describe(fault)
  defp runtime_wrapper_label(nil), do: nil
  defp runtime_wrapper_label(other), do: Fault.describe(other)

  defp udp_wrapper_label({:corrupt_next_response, mode}), do: UdpFault.describe(mode)
  defp udp_wrapper_label(nil), do: nil
  defp udp_wrapper_label(other), do: UdpFault.describe(other)

  defp raw_fault_summary([], mode) do
    case mode do
      :redundant -> "No active raw endpoint delays."
      _other -> "No active raw response delays."
    end
  end

  defp raw_fault_summary(active_endpoints, _mode) do
    active_endpoints
    |> Enum.map(& &1.label)
    |> Enum.join(" | ")
  end

  defp udp_label(%{ip: ip, port: port}), do: "#{format_ip(ip)}:#{port}"
  defp udp_label(_udp), do: "disabled"

  defp format_ip(ip) do
    ip
    |> :inet.ntoa()
    |> to_string()
  end

  defp format_value(value) when is_binary(value), do: inspect(value)
  defp format_value(value), do: inspect(value, limit: 4, printable_limit: 120)

  defp yes_no(true), do: "yes"
  defp yes_no(false), do: "no"

  defp command_offset_payloads(offsets) when map_size(offsets) == 0, do: []

  defp command_offset_payloads(offsets) do
    offsets
    |> Enum.sort_by(fn {command_name, _delta} -> Atom.to_string(command_name) end)
    |> Enum.map(fn {command_name, delta} ->
      %{
        command: Atom.to_string(command_name),
        delta: delta,
        label: Fault.describe({:command_wkc_offset, command_name, delta})
      }
    end)
  end

  defp logical_offset_payloads(offsets) when map_size(offsets) == 0, do: []

  defp logical_offset_payloads(offsets) do
    offsets
    |> Enum.sort_by(fn {slave_name, _delta} -> Atom.to_string(slave_name) end)
    |> Enum.map(fn {slave_name, delta} ->
      %{
        slave: Atom.to_string(slave_name),
        delta: delta,
        label: Fault.describe({:logical_wkc_offset, slave_name, delta})
      }
    end)
  end

  defp scheduled_fault_payloads(entries) when entries == [], do: []

  defp scheduled_fault_payloads(entries) do
    entries
    |> Enum.with_index()
    |> Enum.map(fn {entry, index} -> scheduled_fault_payload(entry, index) end)
  end

  defp scheduled_fault_payload(%{fault: fault} = entry, index) do
    %{
      key: "scheduled-#{index}",
      label: Fault.describe(fault),
      schedule: scheduled_fault_schedule(entry),
      remaining: scheduled_fault_remaining(entry)
    }
  end

  defp scheduled_fault_schedule(%{due_in_ms: due_in_ms}) when is_integer(due_in_ms),
    do: "in #{due_in_ms} ms"

  defp scheduled_fault_schedule(%{waiting_on: milestone}),
    do: "after #{milestone_label(milestone)}"

  defp scheduled_fault_schedule(_entry), do: "scheduled"

  defp scheduled_fault_remaining(%{remaining: remaining}) when is_integer(remaining),
    do: Integer.to_string(remaining)

  defp scheduled_fault_remaining(_entry), do: "-"

  defp milestone_label({:healthy_exchanges, count}), do: "#{count} healthy exchanges"

  defp milestone_label({:healthy_polls, slave_name, count}),
    do: "#{count} healthy polls for #{slave_name}"

  defp milestone_label({:mailbox_step, slave_name, step, count}),
    do: "#{count} mailbox #{step} steps for #{slave_name}"

  defp milestone_label({:queued_exchange_steps, count}),
    do: "#{count} queued exchange steps"

  defp milestone_label(other), do: inspect(other)

  defp offline_message(_reason, %{level: "error"} = message), do: message
  defp offline_message(reason, _message), do: error_message("Simulator unavailable: #{reason}.")

  defp error_message(text), do: %{level: "error", text: text}

  defp hex(value) do
    digits =
      value
      |> Integer.to_string(16)
      |> String.upcase()
      |> String.pad_leading(4, "0")

    "0x" <> digits
  end

  defp maybe_prepend(list, true, value), do: [value | list]
  defp maybe_prepend(list, false, _value), do: list
end
