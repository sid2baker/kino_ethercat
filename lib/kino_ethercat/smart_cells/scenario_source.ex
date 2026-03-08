defmodule KinoEtherCAT.SmartCells.ScenarioSource do
  @moduledoc false

  alias KinoEtherCAT.SmartCells.Source

  @telemetry_groups [:bus, :dc, :domain, :slave]

  @spec render(map()) :: String.t()
  def render(attrs) when is_map(attrs) do
    with {:ok, scenario_call} <- scenario_call(attrs) do
      Source.multiline([
        "scenario = #{scenario_call}\n\n",
        "scenario\n",
        run_source(attrs),
        "  |> Kino.render()\n\n",
        "Kino.nothing()\n"
      ])
    else
      :error -> ""
    end
  end

  defp scenario_call(%{"scenario" => "loopback_smoke"} = attrs) do
    with {:ok, output_slave} <- atom_string_option(attrs["output_slave"]),
         {:ok, input_slave} <- atom_string_option(attrs["input_slave"]),
         {:ok, pairs} <- pair_list_literal(attrs["pairs"]),
         {:ok, settle_ms} <- integer_option(attrs["settle_ms"]),
         {:ok, timeout_ms} <- integer_option(attrs["timeout_ms"]) do
      {:ok,
       multiline_call(
         "KinoEtherCAT.Testing.Scenarios.loopback_smoke(",
         [
           "output_slave: #{output_slave}",
           "input_slave: #{input_slave}",
           "pairs: #{pairs}",
           "settle_ms: #{settle_ms}",
           "timeout_ms: #{timeout_ms}"
         ]
       )}
    end
  end

  defp scenario_call(%{"scenario" => "dc_lock"} = attrs) do
    with {:ok, slaves} <- atom_list_literal(attrs["slaves"]),
         {:ok, expected_lock_state} <- atom_string_option(attrs["expected_lock_state"]),
         {:ok, within_ms} <- integer_option(attrs["within_ms"]),
         {:ok, poll_ms} <- integer_option(attrs["poll_ms"]),
         {:ok, timeout_ms} <- integer_option(attrs["timeout_ms"]) do
      {:ok,
       multiline_call(
         "KinoEtherCAT.Testing.Scenarios.dc_lock(",
         [
           "slaves: #{slaves}",
           "expected_lock_state: #{expected_lock_state}",
           "within_ms: #{within_ms}",
           "poll_ms: #{poll_ms}",
           "timeout_ms: #{timeout_ms}"
         ]
       )}
    end
  end

  defp scenario_call(%{"scenario" => "watchdog_recovery"} = attrs) do
    with {:ok, domain_id} <- atom_string_option(attrs["domain_id"]),
         {:ok, output_slave} <- atom_string_option(attrs["output_slave"]),
         {:ok, input_slave} <- atom_string_option(attrs["input_slave"]),
         {:ok, watchdog_slave} <- atom_string_option(attrs["watchdog_slave"]),
         {:ok, pairs} <- pair_list_literal(attrs["pairs"]),
         {:ok, settle_ms} <- integer_option(attrs["settle_ms"]),
         {:ok, trip_timeout_ms} <- integer_option(attrs["trip_timeout_ms"]),
         {:ok, recover_timeout_ms} <- integer_option(attrs["recover_timeout_ms"]),
         {:ok, timeout_ms} <- integer_option(attrs["timeout_ms"]) do
      {:ok,
       multiline_call(
         "KinoEtherCAT.Testing.Scenarios.watchdog_recovery(",
         [
           "domain_id: #{domain_id}",
           "output_slave: #{output_slave}",
           "input_slave: #{input_slave}",
           "watchdog_slave: #{watchdog_slave}",
           "pairs: #{pairs}",
           "settle_ms: #{settle_ms}",
           "trip_timeout_ms: #{trip_timeout_ms}",
           "recover_timeout_ms: #{recover_timeout_ms}",
           "timeout_ms: #{timeout_ms}"
         ]
       )}
    end
  end

  defp scenario_call(_attrs), do: :error

  defp run_source(attrs) do
    case Map.get(attrs, "telemetry", "none") do
      "none" ->
        "  |> KinoEtherCAT.Testing.new()\n"

      "all" ->
        telemetry_groups = Enum.map_join(@telemetry_groups, ", ", &inspect/1)

        "  |> KinoEtherCAT.Testing.new(attach_telemetry: true, telemetry_groups: [#{telemetry_groups}])\n"

      value ->
        case atom_string_option(value) do
          {:ok, group} ->
            "  |> KinoEtherCAT.Testing.new(attach_telemetry: true, telemetry_groups: [#{group}])\n"

          :error ->
            "  |> KinoEtherCAT.Testing.new()\n"
        end
    end
  end

  defp pair_list_literal(value) when is_binary(value) do
    value
    |> parse_pairs()
    |> case do
      [] ->
        :error

      pairs ->
        rendered =
          pairs
          |> Enum.map_join(", ", fn {left, right} ->
            "{#{Source.atom_literal(left)}, #{Source.atom_literal(right)}}"
          end)

        {:ok, "[#{rendered}]"}
    end
  end

  defp pair_list_literal(_value), do: :error

  defp parse_pairs(value) do
    value
    |> split_tokens()
    |> Enum.map(&String.split(&1, ~r/\s*(?:->|:)\s*/, parts: 2))
    |> Enum.flat_map(fn
      [left, right] ->
        left = String.trim(left)
        right = String.trim(right)

        if left == "" or right == "" do
          []
        else
          [{left, right}]
        end

      _parts ->
        []
    end)
  end

  defp atom_list_literal(value) when is_binary(value) do
    value
    |> split_tokens()
    |> Enum.reject(&(&1 == ""))
    |> case do
      [] ->
        :error

      names ->
        {:ok, "[" <> Enum.map_join(names, ", ", &Source.atom_literal/1) <> "]"}
    end
  end

  defp atom_list_literal(_value), do: :error

  defp atom_string_option(value) when is_binary(value) do
    case String.trim(value) do
      "" -> :error
      trimmed -> {:ok, Source.atom_literal(trimmed)}
    end
  end

  defp atom_string_option(_value), do: :error

  defp integer_option(value) when is_integer(value), do: {:ok, Source.integer_literal(value)}

  defp integer_option(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed > 0 -> {:ok, Source.integer_literal(parsed)}
      _ -> :error
    end
  end

  defp integer_option(_value), do: :error

  defp split_tokens(value) do
    value
    |> String.split(~r/[\n,]+/)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp multiline_call(prefix, arguments) do
    [
      prefix,
      "\n  ",
      Enum.join(arguments, ",\n  "),
      "\n)"
    ]
    |> IO.iodata_to_binary()
  end
end
