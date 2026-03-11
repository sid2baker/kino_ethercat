defmodule KinoEtherCAT.Simulator.FaultsView do
  @moduledoc false

  alias EtherCAT.Simulator
  alias EtherCAT.Simulator.Udp
  alias KinoEtherCAT.Simulator.Snapshot

  @default_al_error_code 0x001B
  @default_mailbox_index 0x1600
  @default_mailbox_subindex 0x00
  @default_mailbox_abort_code 0x0601_0002
  @udp_fault_modes [:truncate, :unsupported_type, :wrong_idx, :replay_previous]

  @spec payload(map() | nil) :: map()
  def payload(message \\ nil), do: Snapshot.payload(message)

  @spec perform(String.t(), map()) :: map()
  def perform("inject_drop_responses", _params) do
    invoke(
      fn -> Simulator.inject_fault(:drop_responses) end,
      info_message("Dropped responses enabled.")
    )
  end

  def perform("clear_faults", _params) do
    invoke_many(
      [
        {fn -> Simulator.clear_faults() end, []},
        {fn -> Udp.clear_faults() end, [optional: true]}
      ],
      info_message("Runtime and UDP faults cleared.")
    )
  end

  def perform("clear_runtime_faults", _params) do
    invoke(fn -> Simulator.clear_faults() end, info_message("Runtime faults cleared."))
  end

  def perform("clear_udp_faults", _params) do
    invoke(fn -> Udp.clear_faults() end, info_message("UDP faults cleared."))
  end

  def perform("set_wkc_offset", %{"value" => raw_value}) do
    with {:ok, delta} <- parse_integer(raw_value) do
      invoke(
        fn -> Simulator.inject_fault({:wkc_offset, delta}) end,
        info_message("WKC offset set to #{delta}.")
      )
    else
      {:error, :invalid_integer} ->
        error_message("WKC offset must be a signed integer.")
    end
  end

  def perform("inject_disconnect", %{"slave" => raw_slave}) do
    with {:ok, slave_name} <- resolve_slave_name(raw_slave) do
      invoke(
        fn -> Simulator.inject_fault({:disconnect, slave_name}) end,
        info_message("Disconnected #{raw_slave}.")
      )
    else
      {:error, :invalid_slave} ->
        error_message("Select a known simulator slave.")
    end
  end

  def perform("queue_runtime_fault", params) do
    with {:ok, fault} <- build_runtime_fault_plan(params) do
      invoke(
        fn -> Simulator.inject_fault(fault) end,
        info_message("Queued #{planned_runtime_fault_label(fault)}.")
      )
    else
      {:error, :invalid_fault_type} ->
        error_message("Select a runtime fault to queue.")

      {:error, :invalid_slave} ->
        error_message("Select a known simulator slave.")

      {:error, :invalid_integer} ->
        error_message("Runtime fault values must be valid integers.")

      {:error, :invalid_count} ->
        error_message("Queued runtime fault count must be a positive integer.")
    end
  end

  def perform("queue_udp_fault", params) do
    with {:ok, fault} <- build_udp_fault_plan(params) do
      invoke(
        fn -> Udp.inject_fault(fault) end,
        info_message("Queued #{planned_udp_fault_label(fault)}.")
      )
    else
      {:error, :invalid_fault_type} ->
        error_message("Select a UDP reply fault to queue.")

      {:error, :invalid_count} ->
        error_message("Queued UDP fault count must be a positive integer.")
    end
  end

  def perform("retreat_to_safeop", %{"slave" => raw_slave}) do
    with {:ok, slave_name} <- resolve_slave_name(raw_slave) do
      invoke(
        fn -> Simulator.inject_fault({:retreat_to_safeop, slave_name}) end,
        info_message("#{raw_slave} forced back to SAFEOP.")
      )
    else
      {:error, :invalid_slave} ->
        error_message("Select a known simulator slave.")
    end
  end

  def perform("inject_al_error", %{"slave" => raw_slave, "code" => raw_code}) do
    with {:ok, slave_name} <- resolve_slave_name(raw_slave),
         {:ok, code} <- parse_non_neg_integer(raw_code, @default_al_error_code) do
      invoke(
        fn -> Simulator.inject_fault({:latch_al_error, slave_name, code}) end,
        info_message("Latched AL error #{hex(code)} on #{raw_slave}.")
      )
    else
      {:error, :invalid_slave} ->
        error_message("Select a known simulator slave.")

      {:error, :invalid_integer} ->
        error_message("AL error code must be decimal or 0x-prefixed hex.")
    end
  end

  def perform("inject_mailbox_abort", %{
        "slave" => raw_slave,
        "index" => raw_index,
        "subindex" => raw_subindex,
        "abort_code" => raw_abort_code
      }) do
    with {:ok, slave_name} <- resolve_slave_name(raw_slave),
         {:ok, index} <- parse_non_neg_integer(raw_index, @default_mailbox_index),
         {:ok, subindex} <- parse_non_neg_integer(raw_subindex, @default_mailbox_subindex),
         {:ok, abort_code} <- parse_non_neg_integer(raw_abort_code, @default_mailbox_abort_code) do
      invoke(
        fn ->
          Simulator.inject_fault({:mailbox_abort, slave_name, index, subindex, abort_code})
        end,
        info_message(
          "Injected mailbox abort #{hex(abort_code)} on #{raw_slave} for #{hex(index)}:#{hex_byte(subindex)}."
        )
      )
    else
      {:error, :invalid_slave} ->
        error_message("Select a known simulator slave.")

      {:error, :invalid_integer} ->
        error_message("Mailbox values must be decimal or 0x-prefixed hex.")
    end
  end

  def perform(_action, _params), do: error_message("Unknown simulator action.")

  defp build_runtime_fault_plan(params) do
    with {:ok, fault} <- build_runtime_fault(params),
         {:ok, plan} <- parse_queue_plan(Map.get(params, "plan"), Map.get(params, "count")) do
      case plan do
        :next -> {:ok, {:next_exchange, fault}}
        {:count, count} -> {:ok, {:next_exchanges, count, fault}}
      end
    end
  end

  defp build_runtime_fault(%{"kind" => "drop_responses"}), do: {:ok, :drop_responses}

  defp build_runtime_fault(%{"kind" => "wkc_offset", "value" => raw_value}) do
    with {:ok, delta} <- parse_integer(raw_value) do
      {:ok, {:wkc_offset, delta}}
    end
  end

  defp build_runtime_fault(%{"kind" => "disconnect", "slave" => raw_slave}) do
    with {:ok, slave_name} <- resolve_slave_name(raw_slave) do
      {:ok, {:disconnect, slave_name}}
    end
  end

  defp build_runtime_fault(_params), do: {:error, :invalid_fault_type}

  defp build_udp_fault_plan(params) do
    with {:ok, mode} <- parse_udp_fault_mode(Map.get(params, "mode")),
         {:ok, plan} <- parse_queue_plan(Map.get(params, "plan"), Map.get(params, "count")) do
      case plan do
        :next -> {:ok, {:corrupt_next_response, mode}}
        {:count, count} -> {:ok, {:corrupt_next_responses, count, mode}}
      end
    end
  end

  defp parse_queue_plan("count", raw_count) do
    with {:ok, count} <- parse_positive_integer(raw_count) do
      {:ok, {:count, count}}
    else
      {:error, :invalid_integer} -> {:error, :invalid_count}
    end
  end

  defp parse_queue_plan(_plan, _raw_count), do: {:ok, :next}

  defp parse_udp_fault_mode(raw_mode) when is_binary(raw_mode) do
    mode =
      raw_mode
      |> String.trim()
      |> String.to_existing_atom()

    if mode in @udp_fault_modes do
      {:ok, mode}
    else
      {:error, :invalid_fault_type}
    end
  rescue
    ArgumentError -> {:error, :invalid_fault_type}
  end

  defp parse_udp_fault_mode(_raw_mode), do: {:error, :invalid_fault_type}

  defp planned_runtime_fault_label({:next_exchange, fault}),
    do: "next exchange #{runtime_fault_label(fault)}"

  defp planned_runtime_fault_label({:next_exchanges, count, fault}),
    do: "next #{count} exchanges #{runtime_fault_label(fault)}"

  defp planned_runtime_fault_label(other), do: inspect(other)

  defp planned_udp_fault_label({:corrupt_next_response, mode}),
    do: "next UDP reply #{udp_mode_label(mode)}"

  defp planned_udp_fault_label({:corrupt_next_responses, count, mode}),
    do: "next #{count} UDP replies #{udp_mode_label(mode)}"

  defp planned_udp_fault_label(other), do: inspect(other)

  defp runtime_fault_label(:drop_responses), do: "drop responses"
  defp runtime_fault_label({:wkc_offset, delta}), do: "WKC offset #{delta}"
  defp runtime_fault_label({:disconnect, slave_name}), do: "disconnect #{slave_name}"
  defp runtime_fault_label(other), do: inspect(other)

  defp udp_mode_label(:truncate), do: "truncate reply"
  defp udp_mode_label(:unsupported_type), do: "unsupported reply type"
  defp udp_mode_label(:wrong_idx), do: "wrong datagram index"
  defp udp_mode_label(:replay_previous), do: "replay previous response"
  defp udp_mode_label(other), do: inspect(other)

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

  defp parse_integer(value) when is_integer(value), do: {:ok, value}

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} -> {:ok, parsed}
      _ -> {:error, :invalid_integer}
    end
  end

  defp parse_integer(_value), do: {:error, :invalid_integer}

  defp parse_positive_integer(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp parse_positive_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed > 0 -> {:ok, parsed}
      _ -> {:error, :invalid_integer}
    end
  end

  defp parse_positive_integer(_value), do: {:error, :invalid_integer}

  defp parse_non_neg_integer(value, _default) when is_integer(value) and value >= 0,
    do: {:ok, value}

  defp parse_non_neg_integer("", default), do: {:ok, default}
  defp parse_non_neg_integer(nil, default), do: {:ok, default}

  defp parse_non_neg_integer(value, default) when is_binary(value) do
    value = String.trim(value)

    cond do
      value == "" ->
        {:ok, default}

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

  defp parse_non_neg_integer(_value, _default), do: {:error, :invalid_integer}

  defp info_message(text), do: %{level: "info", text: text}
  defp error_message(text), do: %{level: "error", text: text}

  defp hex(value) do
    digits =
      value
      |> Integer.to_string(16)
      |> String.upcase()
      |> String.pad_leading(4, "0")

    "0x" <> digits
  end

  defp hex_byte(value) do
    value
    |> Integer.to_string(16)
    |> String.upcase()
    |> String.pad_leading(2, "0")
    |> then(&("0x" <> &1))
  end
end
