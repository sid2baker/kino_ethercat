defmodule KinoEtherCAT.SmartCells.Scenario do
  use Kino.JS, assets_path: "lib/assets/explorer_cell/build"
  use Kino.JS.Live
  use Kino.SmartCell, name: "EtherCAT Scenario"

  alias KinoEtherCAT.SmartCells.ScenarioSource

  @scenario_options [
    %{value: "loopback_smoke", label: "Loopback smoke"},
    %{value: "dc_lock", label: "DC lock"},
    %{value: "watchdog_recovery", label: "Watchdog recovery"}
  ]

  @telemetry_options [
    %{value: "none", label: "No telemetry"},
    %{value: "bus", label: "Bus telemetry"},
    %{value: "dc", label: "DC telemetry"},
    %{value: "domain", label: "Domain telemetry"},
    %{value: "slave", label: "Slave telemetry"},
    %{value: "all", label: "All telemetry"}
  ]

  @impl true
  def init(attrs, ctx) do
    {:ok, assign(ctx, attrs: normalize_attrs(attrs))}
  end

  @impl true
  def handle_connect(ctx) do
    {:ok, payload(ctx.assigns.attrs), ctx}
  end

  @impl true
  def handle_event("update", params, ctx) do
    attrs =
      ctx.assigns.attrs
      |> Map.merge(params)
      |> normalize_attrs()

    ctx = assign(ctx, attrs: attrs)
    broadcast_event(ctx, "snapshot", payload(attrs))
    {:noreply, ctx}
  end

  @impl true
  def to_attrs(ctx), do: ctx.assigns.attrs

  @impl true
  def to_source(attrs), do: ScenarioSource.render(attrs)

  defp payload(attrs) do
    %{
      title: "Test Scenario",
      description:
        "Pick a built-in EtherCAT validation flow and generate a renderable testing run for the current notebook.",
      values: attrs,
      fields:
        [
          %{
            name: "scenario",
            label: "Scenario",
            type: "select",
            options: @scenario_options
          },
          %{
            name: "telemetry",
            label: "Telemetry",
            type: "select",
            options: @telemetry_options,
            help: "Attach runtime telemetry to the run report."
          }
        ] ++ scenario_fields(attrs)
    }
  end

  defp scenario_fields(%{"scenario" => "dc_lock"} = attrs) do
    [
      %{
        name: "slaves",
        label: "Slaves",
        type: "textarea",
        placeholder: "coupler, inputs, outputs",
        help: "Comma or newline separated slave names to confirm in OP before checking DC lock."
      },
      %{
        name: "expected_lock_state",
        label: "Expected Lock",
        type: "select",
        options: [
          %{value: "locked", label: "Locked"},
          %{value: "locking", label: "Locking"},
          %{value: "unavailable", label: "Unavailable"},
          %{value: "disabled", label: "Disabled"}
        ]
      },
      integer_field("within_ms", "Wait Timeout", attrs["within_ms"], "2000"),
      integer_field("poll_ms", "Poll Interval", attrs["poll_ms"], "50"),
      integer_field("timeout_ms", "Scenario Timeout", attrs["timeout_ms"], "15000")
    ]
  end

  defp scenario_fields(%{"scenario" => "watchdog_recovery"} = attrs) do
    [
      text_field(
        "domain_id",
        "Domain",
        attrs["domain_id"],
        "main",
        "The domain that will be stopped and restarted to trip the watchdog."
      ),
      text_field("output_slave", "Output Slave", attrs["output_slave"], "outputs"),
      text_field("input_slave", "Input Slave", attrs["input_slave"], "inputs"),
      text_field("watchdog_slave", "Watchdog Slave", attrs["watchdog_slave"], "outputs"),
      pairs_field(attrs["pairs"]),
      integer_field("settle_ms", "Settle Time", attrs["settle_ms"], "250"),
      integer_field("trip_timeout_ms", "Trip Timeout", attrs["trip_timeout_ms"], "2000"),
      integer_field(
        "recover_timeout_ms",
        "Recovery Timeout",
        attrs["recover_timeout_ms"],
        "5000"
      ),
      integer_field("timeout_ms", "Scenario Timeout", attrs["timeout_ms"], "17000")
    ]
  end

  defp scenario_fields(attrs) do
    [
      text_field("output_slave", "Output Slave", attrs["output_slave"], "outputs"),
      text_field("input_slave", "Input Slave", attrs["input_slave"], "inputs"),
      pairs_field(attrs["pairs"]),
      integer_field("settle_ms", "Settle Time", attrs["settle_ms"], "250"),
      integer_field("timeout_ms", "Scenario Timeout", attrs["timeout_ms"], "15000")
    ]
  end

  defp normalize_attrs(attrs) when is_map(attrs) do
    scenario = normalize_choice(Map.get(attrs, "scenario", "loopback_smoke"), @scenario_options)

    defaults =
      %{
        "scenario" => scenario,
        "telemetry" => normalize_choice(Map.get(attrs, "telemetry", "none"), @telemetry_options),
        "output_slave" => "outputs",
        "input_slave" => "inputs",
        "pairs" => "ch1:ch1, ch2:ch2",
        "settle_ms" => "250",
        "timeout_ms" => default_timeout(scenario),
        "slaves" => "coupler, inputs, outputs",
        "expected_lock_state" => "locked",
        "within_ms" => "10000",
        "poll_ms" => "50",
        "domain_id" => "main",
        "watchdog_slave" => "outputs",
        "trip_timeout_ms" => "2000",
        "recover_timeout_ms" => "5000"
      }

    Map.merge(defaults, sanitize_string_values(attrs))
    |> Map.put("scenario", scenario)
    |> Map.put(
      "telemetry",
      normalize_choice(Map.get(attrs, "telemetry", "none"), @telemetry_options)
    )
    |> Map.put(
      "timeout_ms",
      Map.get(attrs, "timeout_ms", default_timeout(scenario)) |> to_string()
    )
  end

  defp normalize_choice(value, options) do
    allowed = MapSet.new(Enum.map(options, & &1.value))
    value = value |> to_string() |> String.trim()

    if MapSet.member?(allowed, value) do
      value
    else
      options |> List.first() |> Map.fetch!(:value)
    end
  end

  defp sanitize_string_values(attrs) do
    Map.new(attrs, fn {key, value} -> {key, to_string(value)} end)
  end

  defp default_timeout("dc_lock"), do: "15000"
  defp default_timeout("watchdog_recovery"), do: "17000"
  defp default_timeout(_scenario), do: "15000"

  defp text_field(name, label, value, placeholder, help \\ nil) do
    %{
      name: name,
      label: label,
      type: "text",
      placeholder: placeholder,
      help: help,
      value: value
    }
  end

  defp integer_field(name, label, value, placeholder) do
    %{
      name: name,
      label: label,
      type: "text",
      placeholder: placeholder,
      help: "Positive integer value in milliseconds.",
      value: value
    }
  end

  defp pairs_field(value) do
    %{
      name: "pairs",
      label: "Signal Pairs",
      type: "textarea",
      placeholder: "ch1:ch1, ch2:ch2",
      help:
        "Comma or newline separated output:input mappings. Use output:input or output->input.",
      value: value
    }
  end
end
