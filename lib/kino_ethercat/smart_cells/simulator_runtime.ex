defmodule KinoEtherCAT.SmartCells.SimulatorRuntime do
  @moduledoc false

  alias EtherCAT.Simulator

  @type message :: %{level: String.t(), text: String.t()} | nil

  @spec payload([map()], message()) :: map()
  def payload(configured_entries, message \\ nil) when is_list(configured_entries) do
    configured_entries
    |> Enum.map(& &1.default_name)
    |> payload_for_names(message)
  end

  defp payload_for_names(configured_names, message) do
    case Simulator.info() do
      {:ok, info} ->
        running_payload(info, configured_names, message)

      {:error, reason} ->
        offline_payload(reason, configured_names, offline_message(message))
    end
  rescue
    _error ->
      offline_payload(:not_found, configured_names, offline_message(message))
  end

  @spec perform(String.t()) :: message()
  def perform("stop_runtime") do
    invoke(&Simulator.stop/0, info_message("Simulator stopped."))
  end

  def perform("clear_faults") do
    invoke(&Simulator.clear_faults/0, info_message("Simulator faults cleared."))
  end

  def perform(_action), do: error_message("Unknown simulator action.")

  defp running_payload(info, configured_names, message) do
    slaves = Map.get(info, :slaves, [])
    connections = Map.get(info, :connections, [])
    subscriptions = Map.get(info, :subscriptions, [])
    disconnected = Map.get(info, :disconnected, [])
    drop_responses? = Map.get(info, :drop_responses?, false)
    wkc_offset = Map.get(info, :wkc_offset, 0)
    running_names = Enum.map(slaves, &Atom.to_string(&1.name))
    fault_count = fault_count(drop_responses?, wkc_offset, disconnected)

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
      matches_selection: configured_names == running_names,
      sync_message: sync_message(configured_names, running_names),
      sync_tone: sync_tone(configured_names, running_names),
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

  defp offline_payload(reason, configured_names, message) do
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
      matches_selection: configured_names == [],
      sync_message: sync_message(configured_names, []),
      sync_tone: sync_tone(configured_names, []),
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

  defp sync_message([], []), do: "Add devices and evaluate the cell to start a simulator ring."

  defp sync_message(configured_names, []) when configured_names != [] do
    "Run the smart cell to start the configured simulator ring."
  end

  defp sync_message(configured_names, running_names) when configured_names == running_names do
    "Running simulator matches the configured device order."
  end

  defp sync_message(_configured_names, _running_names) do
    "Running simulator differs from the configured device order. Re-evaluate the cell to apply changes."
  end

  defp sync_tone([], []), do: "info"
  defp sync_tone(configured_names, []) when configured_names != [], do: "warn"

  defp sync_tone(configured_names, running_names) when configured_names == running_names,
    do: "info"

  defp sync_tone(_configured_names, _running_names), do: "warn"

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
end
