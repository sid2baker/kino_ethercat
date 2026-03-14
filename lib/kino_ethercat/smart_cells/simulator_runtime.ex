defmodule KinoEtherCAT.SmartCells.SimulatorRuntime do
  @moduledoc false

  alias EtherCAT.Simulator
  alias EtherCAT.Simulator.Udp

  @type message :: %{level: String.t(), text: String.t()} | nil

  @spec payload([map()], [map()], String.t(), message()) :: map()
  def payload(configured_entries, configured_connections, configured_transport, message \\ nil)
      when is_list(configured_entries) and is_list(configured_connections) do
    payload_for_config(
      Enum.map(configured_entries, & &1.name),
      Enum.map(
        configured_connections,
        &connection_key(&1.source_name, &1.source_signal, &1.target_name, &1.target_signal)
      ),
      configured_transport,
      message
    )
  end

  defp payload_for_config(
         configured_names,
         configured_connection_keys,
         configured_transport,
         message
       ) do
    case Simulator.info() do
      {:ok, info} ->
        running_payload(
          info,
          configured_names,
          configured_connection_keys,
          configured_transport,
          message
        )

      {:error, reason} ->
        offline_payload(
          reason,
          configured_names,
          configured_connection_keys,
          configured_transport,
          offline_message(message)
        )
    end
  rescue
    _error ->
      offline_payload(
        :not_found,
        configured_names,
        configured_connection_keys,
        configured_transport,
        offline_message(message)
      )
  end

  @spec perform(String.t()) :: message()
  def perform("stop_runtime") do
    invoke(&Simulator.stop/0, info_message("Simulator stopped."))
  end

  def perform("clear_faults") do
    invoke_many(
      [
        {&Simulator.clear_faults/0, []},
        {&Udp.clear_faults/0, [optional: true]}
      ],
      info_message("Runtime and UDP faults cleared.")
    )
  end

  def perform(_action), do: error_message("Unknown simulator action.")

  defp running_payload(
         info,
         configured_names,
         configured_connection_keys,
         configured_transport,
         message
       ) do
    slaves = Map.get(info, :slaves, [])
    connections = Map.get(info, :connections, [])
    subscriptions = Map.get(info, :subscriptions, [])
    running_names = Enum.map(slaves, &Atom.to_string(&1.name))
    running_connection_keys = Enum.map(connections, &connection_key(&1.source, &1.target))
    running_transport = running_transport(info)
    fault_counts = fault_counts(info)

    config_matches? =
      configured_names == running_names and
        sort_keys(configured_connection_keys) == sort_keys(running_connection_keys) and
        configured_transport == running_transport

    %{
      status: "running",
      summary:
        transport_summary(info) ++
          [
            %{label: "Slaves", value: Integer.to_string(length(slaves))},
            %{label: "Connections", value: Integer.to_string(length(connections))},
            %{label: "Subscriptions", value: Integer.to_string(length(subscriptions))},
            %{label: "Faults", value: Integer.to_string(fault_counts.total)}
          ],
      configured_names: configured_names,
      running_names: running_names,
      configured_transport: configured_transport,
      running_transport: running_transport,
      configured_connection_count: length(configured_connection_keys),
      running_connection_count: length(running_connection_keys),
      matches_selection: config_matches?,
      sync_message:
        sync_message(
          configured_names,
          running_names,
          configured_connection_keys,
          running_connection_keys,
          configured_transport,
          running_transport
        ),
      sync_tone:
        sync_tone(
          configured_names,
          running_names,
          configured_connection_keys,
          running_connection_keys,
          configured_transport,
          running_transport
        ),
      message: message,
      faults: %{
        active_count: fault_counts.total,
        runtime_sticky_count: fault_counts.runtime_sticky,
        runtime_pending_count: fault_counts.runtime_pending,
        udp_pending_count: fault_counts.udp_pending,
        summary: fault_summary(fault_counts)
      }
    }
  end

  defp offline_payload(
         reason,
         configured_names,
         configured_connection_keys,
         configured_transport,
         message
       ) do
    %{
      status: "offline",
      reason: to_string(reason),
      summary: [
        %{label: "Transport", value: "offline"},
        %{label: "Slaves", value: "0"},
        %{label: "Connections", value: "0"},
        %{label: "Subscriptions", value: "0"},
        %{label: "Faults", value: "0"}
      ],
      configured_names: configured_names,
      running_names: [],
      configured_transport: configured_transport,
      running_transport: nil,
      configured_connection_count: length(configured_connection_keys),
      running_connection_count: 0,
      matches_selection: configured_names == [] and configured_connection_keys == [],
      sync_message:
        sync_message(
          configured_names,
          [],
          configured_connection_keys,
          [],
          configured_transport,
          nil
        ),
      sync_tone:
        sync_tone(configured_names, [], configured_connection_keys, [], configured_transport, nil),
      message: message,
      faults: %{
        active_count: 0,
        runtime_sticky_count: 0,
        runtime_pending_count: 0,
        udp_pending_count: 0,
        summary: "No active faults."
      }
    }
  end

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

  defp raw_transport_rows(%{interface: interface} = raw) do
    ingress = Map.get(raw, :ingress, :primary)
    [%{label: "Raw (#{ingress})", value: to_string(interface)}]
  end

  defp raw_transport_rows(raw) when is_map(raw) do
    raw
    |> Enum.sort_by(fn {name, _} -> name end)
    |> Enum.map(fn {name, endpoint_info} ->
      interface = Map.get(endpoint_info, :interface, "active")
      %{label: "Raw (#{name})", value: to_string(interface)}
    end)
  end

  defp topology_rows(%{mode: :redundant, break_after: break_after}) do
    value = if break_after, do: "redundant (break after #{break_after})", else: "redundant"
    [%{label: "Topology", value: value}]
  end

  defp topology_rows(%{mode: :linear}), do: [%{label: "Topology", value: "linear"}]
  defp topology_rows(_topology), do: []

  defp fault_counts(info) do
    runtime_sticky =
      if(Map.get(info, :drop_responses?, false), do: 1, else: 0) +
        if(Map.get(info, :wkc_offset, 0) != 0, do: 1, else: 0) +
        length(Map.get(info, :disconnected, []))

    runtime_pending =
      length(Map.get(info, :pending_faults, [])) +
        if(is_nil(Map.get(info, :next_fault)), do: 0, else: 1)

    udp_pending = length(get_in(info, [:udp, :pending_faults]) || [])

    %{
      runtime_sticky: runtime_sticky,
      runtime_pending: runtime_pending,
      udp_pending: udp_pending,
      total: runtime_sticky + runtime_pending + udp_pending
    }
  end

  defp fault_summary(%{total: 0}), do: "No active faults."

  defp fault_summary(%{
         runtime_sticky: runtime_sticky,
         runtime_pending: runtime_pending,
         udp_pending: udp_pending
       }) do
    []
    |> maybe_prepend(runtime_sticky > 0, "#{runtime_sticky} runtime sticky")
    |> maybe_prepend(runtime_pending > 0, "#{runtime_pending} runtime queued")
    |> maybe_prepend(udp_pending > 0, "#{udp_pending} UDP queued")
    |> Enum.reverse()
    |> Enum.join(" | ")
  end

  defp sync_message([], [], [], [], _configured_transport, _running_transport),
    do: "Add devices and evaluate the cell to start a simulator ring."

  defp sync_message(
         configured_names,
         [],
         _configured_connection_keys,
         [],
         _configured_transport,
         _running_transport
       )
       when configured_names != [] do
    "Run the smart cell to start the configured simulator ring."
  end

  defp sync_message(
         configured_names,
         running_names,
         configured_connection_keys,
         running_connection_keys,
         configured_transport,
         running_transport
       ) do
    if configured_names == running_names and
         sort_keys(configured_connection_keys) == sort_keys(running_connection_keys) and
         configured_transport == running_transport do
      "Running simulator matches the configured ring, connections, and transport."
    else
      "Running simulator differs from the configured ring, connections, or transport. Re-evaluate the cell to apply changes."
    end
  end

  defp sync_tone([], [], [], [], _configured_transport, _running_transport), do: "info"

  defp sync_tone(
         configured_names,
         [],
         _configured_connection_keys,
         [],
         _configured_transport,
         _running_transport
       )
       when configured_names != [], do: "warn"

  defp sync_tone(
         configured_names,
         running_names,
         configured_connection_keys,
         running_connection_keys,
         configured_transport,
         running_transport
       ) do
    if configured_names == running_names and
         sort_keys(configured_connection_keys) == sort_keys(running_connection_keys) and
         configured_transport == running_transport do
      "info"
    else
      "warn"
    end
  end

  defp udp_label(%{ip: ip, port: port}), do: "#{format_ip(ip)}:#{port}"
  defp udp_label(_udp), do: "disabled"

  defp running_transport(%{raw: %{primary: %{}, secondary: %{}}}), do: "raw_socket_redundant"
  defp running_transport(%{raw: %{interface: _interface}}), do: "raw_socket"
  defp running_transport(%{udp: %{}}), do: "udp"
  defp running_transport(_info), do: "disabled"

  defp format_ip(ip) do
    ip
    |> :inet.ntoa()
    |> to_string()
  end

  defp offline_message(%{text: _text} = message), do: message
  defp offline_message(_message), do: nil

  defp invoke(fun, success_message) do
    case normalize_invoke_result(safe_invoke(fun), []) do
      :ok -> success_message
      {:error, :not_found} -> error_message("Simulator unavailable.")
      {:error, reason} -> error_message("Simulator action failed: #{inspect(reason)}")
    end
  end

  defp invoke_many(actions, success_message) do
    case Enum.reduce_while(actions, :ok, fn {fun, opts}, :ok ->
           case normalize_invoke_result(safe_invoke(fun), opts) do
             :ok -> {:cont, :ok}
             {:error, reason} -> {:halt, {:error, reason}}
           end
         end) do
      :ok -> success_message
      {:error, :not_found} -> error_message("Simulator unavailable.")
      {:error, reason} -> error_message("Simulator action failed: #{inspect(reason)}")
    end
  end

  defp normalize_invoke_result(:ok, _opts), do: :ok
  defp normalize_invoke_result({:ok, _value}, _opts), do: :ok

  defp normalize_invoke_result({:error, :not_found}, opts) do
    if Keyword.get(opts, :optional, false), do: :ok, else: {:error, :not_found}
  end

  defp normalize_invoke_result({:error, reason}, _opts), do: {:error, reason}
  defp normalize_invoke_result(other, _opts), do: {:error, other}

  defp safe_invoke(fun) do
    fun.()
  catch
    :exit, {:noproc, _} -> {:error, :not_found}
    :exit, {:timeout, _} -> {:error, :timeout}
  end

  defp info_message(text), do: %{level: "info", text: text}
  defp error_message(text), do: %{level: "error", text: text}

  defp maybe_prepend(list, true, value), do: [value | list]
  defp maybe_prepend(list, false, _value), do: list

  defp connection_key({source_slave, source_signal}, {target_slave, target_signal}) do
    connection_key(
      Atom.to_string(source_slave),
      Atom.to_string(source_signal),
      Atom.to_string(target_slave),
      Atom.to_string(target_signal)
    )
  end

  defp connection_key(source_name, source_signal, target_name, target_signal) do
    "#{source_name}.#{source_signal}->#{target_name}.#{target_signal}"
  end

  defp sort_keys(keys), do: Enum.sort(keys)
end
