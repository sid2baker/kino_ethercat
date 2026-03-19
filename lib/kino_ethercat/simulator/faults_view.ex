defmodule KinoEtherCAT.Simulator.FaultsView do
  @moduledoc false

  alias EtherCAT.Simulator
  alias EtherCAT.Simulator.Fault
  alias EtherCAT.Simulator.Transport.{Raw, Udp}
  alias EtherCAT.Simulator.Transport.Raw.Fault, as: RawFault
  alias EtherCAT.Simulator.Transport.Udp.Fault, as: UdpFault
  alias KinoEtherCAT.Simulator.Snapshot

  @default_al_error_code 0x001B
  @default_mailbox_index 0x1600
  @default_mailbox_subindex 0x00
  @default_mailbox_abort_code 0x0601_0002
  @default_mailbox_fault_value 0x00

  @exchange_commands [
    :aprd,
    :apwr,
    :aprw,
    :fprd,
    :fpwr,
    :fprw,
    :brd,
    :bwr,
    :brw,
    :lrd,
    :lwr,
    :lrw,
    :armw,
    :frmw
  ]

  @mailbox_steps [:request, :upload_init, :upload_segment, :download_init, :download_segment]
  @mailbox_abort_steps [:request, :upload_segment, :download_segment]

  @spec payload(map() | nil) :: map()
  def payload(message \\ nil), do: Snapshot.payload(message)

  @spec perform(String.t(), map()) :: map()
  def perform("apply_runtime_fault", params) do
    with {:ok, fault} <- build_runtime_fault(params) do
      invoke(
        fn -> Simulator.inject_fault(fault) end,
        info_message("Applied #{Fault.describe(fault)}.")
      )
    else
      {:error, reason} -> error_message(runtime_error(reason))
    end
  end

  def perform("apply_transport_fault", params) do
    with {:ok, transport} <- resolve_transport(params),
         {:ok, fault} <- build_transport_fault(transport, params) do
      invoke(
        fn -> inject_transport_fault(transport, fault) end,
        info_message("Applied #{describe_transport_fault(transport, fault)}.")
      )
    else
      {:error, reason} -> error_message(transport_error(reason))
    end
  end

  def perform("apply_udp_fault", params),
    do: perform("apply_transport_fault", Map.put_new(params, "transport", "udp"))

  def perform("inject_drop_responses", _params) do
    perform("apply_runtime_fault", %{"kind" => "drop_responses", "plan" => "immediate"})
  end

  def perform("set_wkc_offset", %{"value" => value}) do
    perform("apply_runtime_fault", %{
      "kind" => "wkc_offset",
      "plan" => "immediate",
      "value" => value
    })
  end

  def perform("inject_disconnect", %{"slave" => slave}) do
    perform("apply_runtime_fault", %{
      "kind" => "disconnect",
      "plan" => "immediate",
      "slave" => slave
    })
  end

  def perform("queue_runtime_fault", params) do
    perform("apply_runtime_fault", Map.put_new(params, "plan", "next"))
  end

  def perform("queue_udp_fault", params) do
    perform("apply_transport_fault", Map.put_new(params, "transport", "udp"))
  end

  def perform("retreat_to_safeop", %{"slave" => slave}) do
    perform("apply_runtime_fault", %{
      "kind" => "retreat_to_safeop",
      "plan" => "immediate",
      "slave" => slave
    })
  end

  def perform("inject_al_error", %{"slave" => slave, "code" => code}) do
    perform("apply_runtime_fault", %{
      "kind" => "latch_al_error",
      "plan" => "immediate",
      "slave" => slave,
      "code" => code
    })
  end

  def perform("inject_mailbox_abort", params) do
    perform(
      "apply_runtime_fault",
      params
      |> Map.put("kind", "mailbox_abort")
      |> Map.put_new("plan", "immediate")
    )
  end

  def perform("clear_faults", _params) do
    invoke_many(
      [
        {fn -> Simulator.clear_faults() end, []},
        {fn -> Udp.clear_faults() end, [optional: true]},
        {fn -> Raw.clear_faults() end, [optional: true]}
      ],
      info_message("Runtime and transport faults cleared.")
    )
  end

  def perform("clear_runtime_faults", _params) do
    invoke(fn -> Simulator.clear_faults() end, info_message("Runtime faults cleared."))
  end

  def perform("clear_transport_faults", _params) do
    invoke_many(
      [
        {fn -> Udp.clear_faults() end, [optional: true]},
        {fn -> Raw.clear_faults() end, [optional: true]}
      ],
      info_message("Transport faults cleared.")
    )
  end

  def perform("clear_udp_faults", _params) do
    perform("clear_transport_faults", %{})
  end

  def perform(_action, _params), do: error_message("Unknown simulator action.")

  defp build_runtime_fault(params) do
    with {:ok, kind} <- parse_runtime_kind(Map.get(params, "kind")),
         {:ok, fault} <- build_runtime_effect(kind, params),
         {:ok, scheduled_fault} <- apply_runtime_plan(kind, fault, params) do
      {:ok, scheduled_fault}
    end
  end

  defp parse_runtime_kind(kind)
       when kind in [
              "drop_responses",
              "wkc_offset",
              "command_wkc_offset",
              "logical_wkc_offset",
              "disconnect",
              "retreat_to_safeop",
              "latch_al_error",
              "mailbox_abort",
              "mailbox_protocol_fault"
            ],
       do: {:ok, kind}

  defp parse_runtime_kind(_kind), do: {:error, :invalid_fault_type}

  defp build_runtime_effect("drop_responses", _params), do: {:ok, Fault.drop_responses()}

  defp build_runtime_effect("wkc_offset", params) do
    with {:ok, delta} <- parse_integer(Map.get(params, "value")) do
      {:ok, Fault.wkc_offset(delta)}
    end
  end

  defp build_runtime_effect("command_wkc_offset", params) do
    with {:ok, command_name} <- parse_exchange_command(Map.get(params, "command")),
         {:ok, delta} <- parse_integer(Map.get(params, "value")) do
      {:ok, Fault.command_wkc_offset(command_name, delta)}
    end
  end

  defp build_runtime_effect("logical_wkc_offset", params) do
    with {:ok, slave_name} <- resolve_slave_name(Map.get(params, "slave")),
         {:ok, delta} <- parse_integer(Map.get(params, "value")) do
      {:ok, Fault.logical_wkc_offset(slave_name, delta)}
    end
  end

  defp build_runtime_effect("disconnect", params) do
    with {:ok, slave_name} <- resolve_slave_name(Map.get(params, "slave")) do
      {:ok, Fault.disconnect(slave_name)}
    end
  end

  defp build_runtime_effect("retreat_to_safeop", params) do
    with {:ok, slave_name} <- resolve_slave_name(Map.get(params, "slave")) do
      {:ok, Fault.retreat_to_safeop(slave_name)}
    end
  end

  defp build_runtime_effect("latch_al_error", params) do
    with {:ok, slave_name} <- resolve_slave_name(Map.get(params, "slave")),
         {:ok, code} <- parse_non_neg_integer(Map.get(params, "code"), @default_al_error_code) do
      {:ok, Fault.latch_al_error(slave_name, code)}
    end
  end

  defp build_runtime_effect("mailbox_abort", params) do
    with {:ok, slave_name} <- resolve_slave_name(Map.get(params, "slave")),
         {:ok, index} <- parse_non_neg_integer(Map.get(params, "index"), @default_mailbox_index),
         {:ok, subindex} <-
           parse_non_neg_integer(Map.get(params, "subindex"), @default_mailbox_subindex),
         {:ok, abort_code} <-
           parse_non_neg_integer(Map.get(params, "abort_code"), @default_mailbox_abort_code),
         {:ok, stage} <- parse_optional_mailbox_abort_stage(Map.get(params, "stage")) do
      opts = if is_nil(stage), do: [], else: [stage: stage]
      {:ok, Fault.mailbox_abort(slave_name, index, subindex, abort_code, opts)}
    end
  end

  defp build_runtime_effect("mailbox_protocol_fault", params) do
    with {:ok, slave_name} <- resolve_slave_name(Map.get(params, "slave")),
         {:ok, index} <- parse_non_neg_integer(Map.get(params, "index"), @default_mailbox_index),
         {:ok, subindex} <-
           parse_non_neg_integer(Map.get(params, "subindex"), @default_mailbox_subindex),
         {:ok, stage} <- parse_mailbox_stage(Map.get(params, "stage")),
         {:ok, fault_kind} <- parse_mailbox_fault_kind(params) do
      {:ok, Fault.mailbox_protocol_fault(slave_name, index, subindex, stage, fault_kind)}
    end
  end

  defp apply_runtime_plan(kind, fault, %{"plan" => "next"}) do
    if exchange_fault_kind?(kind) do
      {:ok, Fault.next(fault)}
    else
      {:error, :unsupported_plan}
    end
  end

  defp apply_runtime_plan(kind, fault, %{"plan" => "count", "count" => raw_count}) do
    if exchange_fault_kind?(kind) do
      with {:ok, count} <- parse_positive_integer(raw_count) do
        {:ok, Fault.next(fault, count)}
      else
        {:error, :invalid_integer} -> {:error, :invalid_count}
      end
    else
      {:error, :unsupported_plan}
    end
  end

  defp apply_runtime_plan(_kind, fault, %{"plan" => "after_ms", "delay_ms" => raw_delay}) do
    with {:ok, delay_ms} <- parse_non_neg_integer(raw_delay, 0) do
      {:ok, Fault.after_ms(fault, delay_ms)}
    end
  end

  defp apply_runtime_plan(_kind, fault, %{"plan" => "after_milestone"} = params) do
    with {:ok, milestone} <- parse_milestone(params) do
      {:ok, Fault.after_milestone(fault, milestone)}
    end
  end

  defp apply_runtime_plan(_kind, fault, %{"plan" => "immediate"}), do: {:ok, fault}
  defp apply_runtime_plan(_kind, fault, %{}), do: {:ok, fault}

  defp apply_runtime_plan(_kind, _fault, _params), do: {:error, :invalid_plan}

  defp exchange_fault_kind?(kind)
       when kind in [
              "drop_responses",
              "wkc_offset",
              "command_wkc_offset",
              "logical_wkc_offset",
              "disconnect"
            ],
       do: true

  defp exchange_fault_kind?(_kind), do: false

  defp resolve_transport(%{"transport" => raw_transport}) when is_binary(raw_transport) do
    case String.trim(raw_transport) do
      "udp" -> ensure_transport_available(:udp)
      "raw" -> ensure_transport_available(:raw)
      _other -> {:error, :invalid_transport}
    end
  end

  defp resolve_transport(_params) do
    case current_transport() do
      {:ok, transport} -> {:ok, transport}
      :error -> {:error, :transport_disabled}
    end
  end

  defp ensure_transport_available(requested_transport) do
    case current_transport() do
      {:ok, ^requested_transport} -> {:ok, requested_transport}
      {:ok, _other_transport} -> {:error, :transport_unavailable}
      :error -> {:error, :transport_disabled}
    end
  end

  defp current_transport do
    with {:ok, info} <- Simulator.info() do
      cond do
        raw_transport_running?(info) -> {:ok, :raw}
        udp_transport_running?(info) -> {:ok, :udp}
        true -> :error
      end
    else
      _error -> :error
    end
  end

  defp build_transport_fault(:udp, params), do: build_udp_fault(params)
  defp build_transport_fault(:raw, params), do: build_raw_fault(params)

  defp inject_transport_fault(:udp, fault), do: Udp.inject_fault(fault)
  defp inject_transport_fault(:raw, fault), do: Raw.inject_fault(fault)

  defp describe_transport_fault(:udp, fault), do: UdpFault.describe(fault)
  defp describe_transport_fault(:raw, fault), do: RawFault.describe(fault)

  defp build_udp_fault(params) do
    with {:ok, mode} <- parse_udp_mode(Map.get(params, "mode")) do
      apply_udp_plan(mode, params)
    end
  end

  defp build_raw_fault(params) do
    with {:ok, kind} <- parse_raw_transport_kind(Map.get(params, "kind")),
         {:ok, delay_ms} <- parse_non_neg_integer(Map.get(params, "delay_ms"), 0),
         {:ok, endpoint} <- parse_raw_selector(Map.get(params, "endpoint"), :all),
         {:ok, from_ingress} <- parse_raw_selector(Map.get(params, "from_ingress"), :all) do
      case kind do
        :delay_response ->
          {:ok, RawFault.delay_response(delay_ms, endpoint: endpoint, from_ingress: from_ingress)}
      end
    end
  end

  defp apply_udp_plan(mode, %{"plan" => "count", "count" => raw_count}) do
    with {:ok, count} <- parse_positive_integer(raw_count) do
      {:ok, UdpFault.next(mode, count)}
    else
      {:error, :invalid_integer} -> {:error, :invalid_count}
    end
  end

  defp apply_udp_plan(_mode, %{"plan" => "script", "script" => raw_script}) do
    with {:ok, steps} <- parse_udp_script(raw_script) do
      {:ok, UdpFault.script(steps)}
    end
  end

  defp apply_udp_plan(mode, %{"plan" => "next"}), do: {:ok, UdpFault.next(mode)}
  defp apply_udp_plan(mode, %{}), do: {:ok, UdpFault.next(mode)}
  defp apply_udp_plan(_mode, _params), do: {:error, :invalid_plan}

  defp parse_exchange_command(raw_command) when is_binary(raw_command) do
    command =
      raw_command
      |> String.trim()
      |> String.downcase()

    case Enum.find(@exchange_commands, &(Atom.to_string(&1) == command)) do
      nil -> {:error, :invalid_command}
      command_name -> {:ok, command_name}
    end
  end

  defp parse_exchange_command(_raw_command), do: {:error, :invalid_command}

  defp parse_optional_mailbox_abort_stage(nil), do: {:ok, nil}
  defp parse_optional_mailbox_abort_stage(""), do: {:ok, nil}

  defp parse_optional_mailbox_abort_stage(raw_stage) when is_binary(raw_stage) do
    with {:ok, stage} <- parse_mailbox_stage(raw_stage) do
      if stage in @mailbox_abort_steps, do: {:ok, stage}, else: {:error, :invalid_stage}
    end
  end

  defp parse_optional_mailbox_abort_stage(_raw_stage), do: {:error, :invalid_stage}

  defp parse_mailbox_stage(raw_stage) when is_binary(raw_stage) do
    stage =
      raw_stage
      |> String.trim()
      |> String.downcase()

    case Enum.find(@mailbox_steps, &(Atom.to_string(&1) == stage)) do
      nil -> {:error, :invalid_stage}
      stage_atom -> {:ok, stage_atom}
    end
  end

  defp parse_mailbox_stage(_raw_stage), do: {:error, :invalid_stage}

  defp parse_mailbox_fault_kind(%{"mailbox_fault_kind" => raw_kind} = params)
       when is_binary(raw_kind) do
    case String.trim(raw_kind) do
      "drop_response" ->
        {:ok, :drop_response}

      "counter_mismatch" ->
        {:ok, :counter_mismatch}

      "toggle_mismatch" ->
        {:ok, :toggle_mismatch}

      "invalid_coe_payload" ->
        {:ok, :invalid_coe_payload}

      "invalid_segment_padding" ->
        {:ok, :invalid_segment_padding}

      "mailbox_type" ->
        parse_mailbox_fault_value(params, :mailbox_type)

      "coe_service" ->
        parse_mailbox_fault_value(params, :coe_service)

      "sdo_command" ->
        parse_mailbox_fault_value(params, :sdo_command)

      "segment_command" ->
        parse_mailbox_fault_value(params, :segment_command)

      _other ->
        {:error, :invalid_mailbox_fault}
    end
  end

  defp parse_mailbox_fault_kind(_params), do: {:error, :invalid_mailbox_fault}

  defp parse_mailbox_fault_value(params, kind) do
    with {:ok, value} <-
           parse_non_neg_integer(
             Map.get(params, "mailbox_fault_value"),
             @default_mailbox_fault_value
           ) do
      {:ok, {kind, value}}
    end
  end

  defp parse_milestone(%{"milestone_kind" => "healthy_exchanges", "milestone_count" => raw_count}) do
    with {:ok, count} <- parse_positive_integer(raw_count) do
      {:ok, Fault.healthy_exchanges(count)}
    end
  end

  defp parse_milestone(%{
         "milestone_kind" => "healthy_polls",
         "milestone_count" => raw_count,
         "milestone_slave" => raw_slave
       }) do
    with {:ok, count} <- parse_positive_integer(raw_count),
         {:ok, slave_name} <- resolve_slave_name(raw_slave) do
      {:ok, Fault.healthy_polls(slave_name, count)}
    end
  end

  defp parse_milestone(%{
         "milestone_kind" => "mailbox_step",
         "milestone_count" => raw_count,
         "milestone_slave" => raw_slave,
         "milestone_stage" => raw_stage
       }) do
    with {:ok, count} <- parse_positive_integer(raw_count),
         {:ok, slave_name} <- resolve_slave_name(raw_slave),
         {:ok, stage} <- parse_mailbox_stage(raw_stage) do
      {:ok, Fault.mailbox_step(slave_name, stage, count)}
    end
  end

  defp parse_milestone(_params), do: {:error, :invalid_milestone}

  defp parse_udp_mode(raw_mode) when is_binary(raw_mode) do
    case String.trim(raw_mode) do
      "truncate" -> {:ok, UdpFault.truncate()}
      "unsupported_type" -> {:ok, UdpFault.unsupported_type()}
      "wrong_idx" -> {:ok, UdpFault.wrong_idx()}
      "replay_previous" -> {:ok, UdpFault.replay_previous()}
      _other -> {:error, :invalid_fault_type}
    end
  end

  defp parse_udp_mode(_raw_mode), do: {:error, :invalid_fault_type}

  defp parse_udp_script(raw_script) when is_binary(raw_script) do
    modes =
      raw_script
      |> String.split(~r/[\s,]+/, trim: true)
      |> Enum.map(&parse_udp_script_mode/1)

    if modes == [] do
      {:error, :invalid_script}
    else
      case Enum.find(modes, &match?({:error, _}, &1)) do
        nil -> {:ok, Enum.map(modes, fn {:ok, mode} -> mode end)}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp parse_udp_script(_raw_script), do: {:error, :invalid_script}

  defp parse_udp_script_mode("truncate"), do: {:ok, UdpFault.truncate()}
  defp parse_udp_script_mode("unsupported_type"), do: {:ok, UdpFault.unsupported_type()}
  defp parse_udp_script_mode("wrong_idx"), do: {:ok, UdpFault.wrong_idx()}
  defp parse_udp_script_mode("replay_previous"), do: {:ok, UdpFault.replay_previous()}
  defp parse_udp_script_mode(_mode), do: {:error, :invalid_script}

  defp parse_raw_transport_kind(nil), do: {:ok, :delay_response}
  defp parse_raw_transport_kind(""), do: {:ok, :delay_response}
  defp parse_raw_transport_kind("delay_response"), do: {:ok, :delay_response}
  defp parse_raw_transport_kind(_kind), do: {:error, :invalid_fault_type}

  defp parse_raw_selector(nil, default), do: {:ok, default}
  defp parse_raw_selector("", default), do: {:ok, default}
  defp parse_raw_selector("all", _default), do: {:ok, :all}
  defp parse_raw_selector("primary", _default), do: {:ok, :primary}
  defp parse_raw_selector("secondary", _default), do: {:ok, :secondary}
  defp parse_raw_selector(_value, _default), do: {:error, :invalid_selector}

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

  defp raw_transport_running?(info) do
    case Map.get(info, :raw) do
      raw when is_map(raw) -> map_size(raw) > 0
      _other -> false
    end
  end

  defp udp_transport_running?(info), do: is_map(Map.get(info, :udp))

  defp runtime_error(:invalid_command), do: "Select a valid EtherCAT command."
  defp runtime_error(:invalid_count), do: "Counts must be positive integers."
  defp runtime_error(:invalid_fault_type), do: "Select a runtime fault."
  defp runtime_error(:invalid_integer), do: "Fault values must be decimal or 0x-prefixed hex."
  defp runtime_error(:invalid_mailbox_fault), do: "Select a valid mailbox protocol fault."
  defp runtime_error(:invalid_milestone), do: "Select a valid milestone trigger."
  defp runtime_error(:invalid_plan), do: "Select a valid runtime fault plan."
  defp runtime_error(:invalid_slave), do: "Select a known simulator slave."
  defp runtime_error(:invalid_stage), do: "Select a valid mailbox stage."

  defp runtime_error(:unsupported_plan),
    do: "Next-exchange plans only work for exchange faults."

  defp runtime_error(other), do: "Runtime fault build failed: #{inspect(other)}"

  defp transport_error(:invalid_count), do: "Transport fault counts must be positive integers."
  defp transport_error(:invalid_fault_type), do: "Select a valid transport fault."

  defp transport_error(:invalid_integer),
    do: "Transport values must be decimal or 0x-prefixed hex."

  defp transport_error(:invalid_plan), do: "Select a valid transport fault plan."
  defp transport_error(:invalid_selector), do: "Select a valid raw transport endpoint or ingress."
  defp transport_error(:invalid_transport), do: "Select a known simulator transport."
  defp transport_error(:transport_disabled), do: "Transport fault injection is unavailable."
  defp transport_error(:transport_unavailable), do: "The selected transport is not active."

  defp transport_error(:invalid_script),
    do: "UDP scripts must be a comma or space separated list of valid reply modes."

  defp transport_error(other), do: "Transport fault build failed: #{inspect(other)}"

  defp info_message(text), do: %{level: "info", text: text}
  defp error_message(text), do: %{level: "error", text: text}
end
