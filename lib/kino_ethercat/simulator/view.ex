defmodule KinoEtherCAT.Simulator.View do
  @moduledoc false

  alias EtherCAT.Simulator

  @default_al_error_code 0x001B

  @spec payload(map() | nil) :: map()
  def payload(message \\ nil) do
    case Simulator.info() do
      {:ok, info} ->
        running_payload(info, message)

      {:error, reason} ->
        offline_payload(reason, offline_message(reason, message))
    end
  end

  @spec perform(String.t(), map()) :: map()
  def perform("inject_drop_responses", _params) do
    invoke(
      fn -> Simulator.inject_fault(:drop_responses) end,
      info_message("Dropped responses enabled.")
    )
  end

  def perform("clear_faults", _params) do
    invoke(fn -> Simulator.clear_faults() end, info_message("Simulator faults cleared."))
  end

  def perform("set_wkc_offset", %{"value" => raw_value}) do
    with {:ok, delta} <- parse_integer(raw_value),
         message <-
           invoke(
             fn -> Simulator.inject_fault({:wkc_offset, delta}) end,
             info_message("WKC offset set to #{delta}.")
           ) do
      message
    else
      {:error, :invalid_integer} ->
        error_message("WKC offset must be a signed integer.")
    end
  end

  def perform("inject_disconnect", %{"slave" => raw_slave}) do
    with {:ok, slave_name} <- resolve_slave_name(raw_slave),
         message <-
           invoke(
             fn -> Simulator.inject_fault({:disconnect, slave_name}) end,
             info_message("Disconnected #{raw_slave}.")
           ) do
      message
    else
      {:error, :invalid_slave} ->
        error_message("Select a known simulator slave.")
    end
  end

  def perform("retreat_to_safeop", %{"slave" => raw_slave}) do
    with {:ok, slave_name} <- resolve_slave_name(raw_slave),
         message <-
           invoke(
             fn -> Simulator.inject_fault({:retreat_to_safeop, slave_name}) end,
             info_message("#{raw_slave} forced back to SAFEOP.")
           ) do
      message
    else
      {:error, :invalid_slave} ->
        error_message("Select a known simulator slave.")
    end
  end

  def perform("inject_al_error", %{"slave" => raw_slave, "code" => raw_code}) do
    with {:ok, slave_name} <- resolve_slave_name(raw_slave),
         {:ok, code} <- parse_non_neg_integer(raw_code),
         message <-
           invoke(
             fn -> Simulator.inject_fault({:latch_al_error, slave_name, code}) end,
             info_message("Latched AL error #{hex(code)} on #{raw_slave}.")
           ) do
      message
    else
      {:error, :invalid_slave} ->
        error_message("Select a known simulator slave.")

      {:error, :invalid_integer} ->
        error_message("AL error code must be decimal or 0x-prefixed hex.")
    end
  end

  def perform(_action, _params), do: error_message("Unknown simulator action.")

  defp running_payload(info, message) do
    slaves = Map.get(info, :slaves, [])
    connections = Map.get(info, :connections, [])
    subscriptions = Map.get(info, :subscriptions, [])
    disconnected = Map.get(info, :disconnected, [])
    drop_responses? = Map.get(info, :drop_responses?, false)
    wkc_offset = Map.get(info, :wkc_offset, 0)

    %{
      title: "EtherCAT Simulator",
      kind: "virtual ring",
      status: "running",
      message: message,
      summary: [
        %{label: "UDP", value: udp_label(Map.get(info, :udp))},
        %{label: "Slaves", value: Integer.to_string(length(slaves))},
        %{label: "Connections", value: Integer.to_string(length(connections))},
        %{label: "Subscriptions", value: Integer.to_string(length(subscriptions))},
        %{label: "Dropped responses", value: yes_no(drop_responses?)},
        %{label: "WKC offset", value: Integer.to_string(wkc_offset)},
        %{label: "Disconnected", value: Integer.to_string(length(disconnected))}
      ],
      faults: %{
        drop_responses?: drop_responses?,
        wkc_offset: wkc_offset,
        disconnected: Enum.map(disconnected, &Atom.to_string/1)
      },
      slave_options: Enum.map(slaves, &Atom.to_string(&1.name)),
      slaves: Enum.map(slaves, &slave_payload/1),
      connections: Enum.map(connections, &connection_payload/1),
      subscriptions: Enum.map(subscriptions, &subscription_payload/1)
    }
  end

  defp offline_payload(reason, message) do
    %{
      title: "EtherCAT Simulator",
      kind: "virtual ring",
      status: "offline",
      reason: to_string(reason),
      message: message,
      summary: [
        %{label: "UDP", value: "disabled"},
        %{label: "Slaves", value: "0"},
        %{label: "Connections", value: "0"},
        %{label: "Subscriptions", value: "0"},
        %{label: "Dropped responses", value: "no"},
        %{label: "WKC offset", value: "0"},
        %{label: "Disconnected", value: "0"}
      ],
      faults: %{drop_responses?: false, wkc_offset: 0, disconnected: []},
      slave_options: [],
      slaves: [],
      connections: [],
      subscriptions: []
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

  defp udp_label(%{ip: ip, port: port}), do: "#{format_ip(ip)}:#{port}"
  defp udp_label(_udp), do: "disabled"

  defp format_ip(ip) do
    ip
    |> :inet.ntoa()
    |> to_string()
  end

  defp format_value(value) when is_binary(value), do: inspect(value)
  defp format_value(value), do: inspect(value, limit: 4, printable_limit: 120)

  defp resolve_slave_name(raw_slave) when is_binary(raw_slave) do
    with {:ok, info} <- Simulator.info(),
         slave when not is_nil(slave) <-
           Enum.find(
             Map.get(info, :slaves, []),
             &(Atom.to_string(&1.name) == String.trim(raw_slave))
           ) do
      {:ok, slave.name}
    else
      _ -> {:error, :invalid_slave}
    end
  end

  defp resolve_slave_name(_raw_slave), do: {:error, :invalid_slave}

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

  defp parse_integer(value) when is_integer(value), do: {:ok, value}

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} -> {:ok, parsed}
      _ -> {:error, :invalid_integer}
    end
  end

  defp parse_integer(_value), do: {:error, :invalid_integer}

  defp parse_non_neg_integer(value) when is_integer(value) and value >= 0, do: {:ok, value}

  defp parse_non_neg_integer(""), do: {:ok, @default_al_error_code}
  defp parse_non_neg_integer(nil), do: {:ok, @default_al_error_code}

  defp parse_non_neg_integer(value) when is_binary(value) do
    value = String.trim(value)

    cond do
      value == "" ->
        {:ok, @default_al_error_code}

      String.starts_with?(value, "0x") or String.starts_with?(value, "0X") ->
        case Integer.parse(String.slice(value, 2..-1//1), 16) do
          {parsed, ""} -> {:ok, parsed}
          _ -> {:error, :invalid_integer}
        end

      true ->
        case Integer.parse(value) do
          {parsed, ""} when parsed >= 0 -> {:ok, parsed}
          _ -> {:error, :invalid_integer}
        end
    end
  end

  defp parse_non_neg_integer(_value), do: {:error, :invalid_integer}

  defp info_message(text), do: %{level: "info", text: text}
  defp error_message(text), do: %{level: "error", text: text}

  defp yes_no(true), do: "yes"
  defp yes_no(false), do: "no"

  defp offline_message(_reason, %{level: "error"} = message), do: message
  defp offline_message(reason, _message), do: error_message("Simulator unavailable: #{reason}.")

  defp hex(value) do
    digits =
      value
      |> Integer.to_string(16)
      |> String.upcase()
      |> String.pad_leading(4, "0")

    "0x" <> digits
  end
end
