defmodule KinoEtherCAT.SmartCells.SimulatorRuntime do
  @moduledoc false

  alias EtherCAT.Simulator

  @type message :: %{level: String.t(), text: String.t()} | nil

  @spec payload([map()], [map()], message()) :: map()
  def payload(configured_entries, configured_connections, message \\ nil)
      when is_list(configured_entries) and is_list(configured_connections) do
    payload_for_config(
      Enum.map(configured_entries, & &1.default_name),
      Enum.map(
        configured_connections,
        &connection_key(&1.source_name, &1.source_signal, &1.target_name, &1.target_signal)
      ),
      message
    )
  end

  defp payload_for_config(configured_names, configured_connection_keys, message) do
    case Simulator.info() do
      {:ok, info} ->
        running_payload(info, configured_names, configured_connection_keys, message)

      {:error, reason} ->
        offline_payload(
          reason,
          configured_names,
          configured_connection_keys,
          offline_message(message)
        )
    end
  rescue
    _error ->
      offline_payload(
        :not_found,
        configured_names,
        configured_connection_keys,
        offline_message(message)
      )
  end

  @spec perform(String.t()) :: message()
  def perform("stop_runtime") do
    invoke(&Simulator.stop/0, info_message("Simulator stopped."))
  end

  def perform("clear_faults") do
    invoke(&Simulator.clear_faults/0, info_message("Simulator faults cleared."))
  end

  def perform(_action), do: error_message("Unknown simulator action.")

  defp running_payload(info, configured_names, configured_connection_keys, message) do
    slaves = Map.get(info, :slaves, [])
    connections = Map.get(info, :connections, [])
    subscriptions = Map.get(info, :subscriptions, [])
    disconnected = Map.get(info, :disconnected, [])
    drop_responses? = Map.get(info, :drop_responses?, false)
    wkc_offset = Map.get(info, :wkc_offset, 0)
    running_names = Enum.map(slaves, &Atom.to_string(&1.name))
    running_connection_keys = Enum.map(connections, &connection_key(&1.source, &1.target))
    fault_count = fault_count(drop_responses?, wkc_offset, disconnected)

    config_matches? =
      configured_names == running_names and
        sort_keys(configured_connection_keys) == sort_keys(running_connection_keys)

    %{
      status: "running",
      summary: [
        %{label: "UDP", value: udp_label(Map.get(info, :udp))},
        %{label: "Slaves", value: Integer.to_string(length(slaves))},
        %{label: "Connections", value: Integer.to_string(length(connections))},
        %{label: "Subscriptions", value: Integer.to_string(length(subscriptions))},
        %{label: "Faults", value: Integer.to_string(fault_count)}
      ],
      configured_names: configured_names,
      running_names: running_names,
      configured_connection_count: length(configured_connection_keys),
      running_connection_count: length(running_connection_keys),
      matches_selection: config_matches?,
      sync_message:
        sync_message(
          configured_names,
          running_names,
          configured_connection_keys,
          running_connection_keys
        ),
      sync_tone:
        sync_tone(
          configured_names,
          running_names,
          configured_connection_keys,
          running_connection_keys
        ),
      message: message,
      faults: %{
        active_count: fault_count,
        drop_responses?: drop_responses?,
        wkc_offset: wkc_offset,
        disconnected: Enum.map(disconnected, &Atom.to_string/1),
        summary: fault_summary(drop_responses?, wkc_offset, disconnected)
      }
    }
  end

  defp offline_payload(reason, configured_names, configured_connection_keys, message) do
    %{
      status: "offline",
      reason: to_string(reason),
      summary: [
        %{label: "UDP", value: "offline"},
        %{label: "Slaves", value: "0"},
        %{label: "Connections", value: "0"},
        %{label: "Subscriptions", value: "0"},
        %{label: "Faults", value: "0"}
      ],
      configured_names: configured_names,
      running_names: [],
      configured_connection_count: length(configured_connection_keys),
      running_connection_count: 0,
      matches_selection: configured_names == [] and configured_connection_keys == [],
      sync_message: sync_message(configured_names, [], configured_connection_keys, []),
      sync_tone: sync_tone(configured_names, [], configured_connection_keys, []),
      message: message,
      faults: %{
        active_count: 0,
        drop_responses?: false,
        wkc_offset: 0,
        disconnected: [],
        summary: "No active faults."
      }
    }
  end

  defp fault_count(drop_responses?, wkc_offset, disconnected) do
    length(disconnected) +
      if(drop_responses?, do: 1, else: 0) +
      if(wkc_offset != 0, do: 1, else: 0)
  end

  defp fault_summary(false, 0, []), do: "No active faults."

  defp fault_summary(drop_responses?, wkc_offset, disconnected) do
    []
    |> maybe_prepend(drop_responses?, "Responses dropped")
    |> maybe_prepend(wkc_offset != 0, "WKC offset #{wkc_offset}")
    |> maybe_prepend(
      disconnected != [],
      "Disconnected: #{Enum.map_join(disconnected, ", ", &Atom.to_string/1)}"
    )
    |> Enum.reverse()
    |> Enum.join(" | ")
  end

  defp sync_message([], [], [], []),
    do: "Add devices and evaluate the cell to start a simulator ring."

  defp sync_message(configured_names, [], _configured_connection_keys, [])
       when configured_names != [] do
    "Run the smart cell to start the configured simulator ring."
  end

  defp sync_message(
         configured_names,
         running_names,
         configured_connection_keys,
         running_connection_keys
       ) do
    if configured_names == running_names and
         sort_keys(configured_connection_keys) == sort_keys(running_connection_keys) do
      "Running simulator matches the configured ring and connections."
    else
      "Running simulator differs from the configured ring or connections. Re-evaluate the cell to apply changes."
    end
  end

  defp sync_tone([], [], [], []), do: "info"

  defp sync_tone(configured_names, [], _configured_connection_keys, [])
       when configured_names != [], do: "warn"

  defp sync_tone(
         configured_names,
         running_names,
         configured_connection_keys,
         running_connection_keys
       ) do
    if configured_names == running_names and
         sort_keys(configured_connection_keys) == sort_keys(running_connection_keys) do
      "info"
    else
      "warn"
    end
  end

  defp udp_label(%{ip: ip, port: port}), do: "#{format_ip(ip)}:#{port}"
  defp udp_label(_udp), do: "disabled"

  defp format_ip(ip) do
    ip
    |> :inet.ntoa()
    |> to_string()
  end

  defp offline_message(%{text: _text} = message), do: message
  defp offline_message(_message), do: nil

  defp invoke(fun, success_message) do
    case safe_invoke(fun) do
      :ok -> success_message
      {:ok, _value} -> success_message
      {:error, :not_found} -> error_message("Simulator unavailable.")
      {:error, reason} -> error_message("Simulator action failed: #{inspect(reason)}")
    end
  end

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
