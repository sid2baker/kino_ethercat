defmodule KinoEtherCAT.Simulator.Snapshot do
  @moduledoc false

  alias EtherCAT.Simulator
  alias EtherCAT.Simulator.Fault
  alias EtherCAT.Simulator.Udp.Fault, as: UdpFault

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
    udp_faults = udp_faults_payload(Map.get(info, :udp))

    %{
      title: "EtherCAT Simulator",
      kind: "virtual ring",
      status: "running",
      message: message,
      summary: [
        %{label: "UDP", value: udp_faults.endpoint},
        %{label: "Slaves", value: Integer.to_string(length(slaves))},
        %{label: "Connections", value: Integer.to_string(length(connections))},
        %{label: "Subscriptions", value: Integer.to_string(length(subscriptions))},
        %{label: "Runtime faults", value: Integer.to_string(runtime_faults.active_count)},
        %{label: "UDP faults", value: Integer.to_string(udp_faults.active_count)}
      ],
      runtime_faults: runtime_faults,
      udp_faults: udp_faults,
      slave_options: Enum.map(slaves, &Atom.to_string(&1.name)),
      slaves: Enum.map(slaves, &slave_payload/1),
      connections: Enum.map(connections, &connection_payload/1),
      subscriptions: Enum.map(subscriptions, &subscription_payload/1)
    }
  end

  defp offline_payload(reason, message) do
    runtime_faults = offline_runtime_faults()
    udp_faults = offline_udp_faults()

    %{
      title: "EtherCAT Simulator",
      kind: "virtual ring",
      status: "offline",
      reason: to_string(reason),
      message: message,
      summary: [
        %{label: "UDP", value: udp_faults.endpoint},
        %{label: "Slaves", value: "0"},
        %{label: "Connections", value: "0"},
        %{label: "Subscriptions", value: "0"},
        %{label: "Runtime faults", value: "0"},
        %{label: "UDP faults", value: "0"}
      ],
      runtime_faults: runtime_faults,
      udp_faults: udp_faults,
      slave_options: [],
      slaves: [],
      connections: [],
      subscriptions: []
    }
  end

  defp runtime_faults_payload(info) do
    disconnected =
      info
      |> Map.get(:disconnected, [])
      |> Enum.map(&Atom.to_string/1)
      |> Enum.sort()

    sticky_labels =
      []
      |> maybe_prepend(Map.get(info, :drop_responses?, false), "Drop responses")
      |> maybe_prepend(
        Map.get(info, :wkc_offset, 0) != 0,
        "WKC offset #{Map.get(info, :wkc_offset, 0)}"
      )
      |> maybe_prepend(disconnected != [], "Disconnected: #{Enum.join(disconnected, ", ")}")
      |> Enum.reverse()

    pending_faults = Map.get(info, :pending_faults, [])
    pending_labels = Enum.map(pending_faults, &Fault.describe/1)

    sticky_count =
      if(Map.get(info, :drop_responses?, false), do: 1, else: 0) +
        if(Map.get(info, :wkc_offset, 0) != 0, do: 1, else: 0) +
        length(disconnected)

    %{
      drop_responses: Map.get(info, :drop_responses?, false),
      wkc_offset: Map.get(info, :wkc_offset, 0),
      disconnected: disconnected,
      sticky_labels: sticky_labels,
      sticky_count: sticky_count,
      next_label: runtime_wrapper_label(Map.get(info, :next_fault)),
      pending_labels: pending_labels,
      pending_count: length(pending_labels),
      active_count: sticky_count + length(pending_labels),
      summary: runtime_fault_summary(sticky_labels, pending_labels, Map.get(info, :next_fault))
    }
  end

  defp offline_runtime_faults do
    %{
      drop_responses: false,
      wkc_offset: 0,
      disconnected: [],
      sticky_labels: [],
      sticky_count: 0,
      next_label: nil,
      pending_labels: [],
      pending_count: 0,
      active_count: 0,
      summary: "No runtime faults."
    }
  end

  defp udp_faults_payload(%{} = udp) do
    pending_faults = Map.get(udp, :pending_faults, [])

    %{
      enabled: true,
      endpoint: udp_label(udp),
      last_response_captured: Map.get(udp, :last_response_captured?, false),
      next_label: udp_wrapper_label(Map.get(udp, :next_fault)),
      pending_labels: Enum.map(pending_faults, &UdpFault.describe/1),
      active_count: length(pending_faults),
      summary: udp_fault_summary(pending_faults, Map.get(udp, :next_fault))
    }
  end

  defp udp_faults_payload(_udp), do: offline_udp_faults()

  defp offline_udp_faults do
    %{
      enabled: false,
      endpoint: "disabled",
      last_response_captured: false,
      next_label: nil,
      pending_labels: [],
      active_count: 0,
      summary: "UDP disabled."
    }
  end

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

  defp runtime_fault_summary([], [], _next_fault), do: "No runtime faults."

  defp runtime_fault_summary(sticky_labels, pending_labels, next_fault) do
    []
    |> maybe_prepend(sticky_labels != [], Enum.join(sticky_labels, " | "))
    |> maybe_prepend(
      pending_labels != [],
      "#{length(pending_labels)} queued exchange fault(s)" <>
        case runtime_wrapper_label(next_fault) do
          nil -> ""
          next_label -> " (next: #{next_label})"
        end
    )
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
