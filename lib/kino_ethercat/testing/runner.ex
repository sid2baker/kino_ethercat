defmodule KinoEtherCAT.Testing.Runner do
  @moduledoc false

  alias KinoEtherCAT.Testing.{Report, Run, Scenario, Step}

  @telemetry_groups [:bus, :dc, :domain, :slave]

  @fallback_telemetry_events [
    [:ethercat, :bus, :transact, :start],
    [:ethercat, :bus, :transact, :stop],
    [:ethercat, :bus, :transact, :exception],
    [:ethercat, :bus, :submission, :enqueued],
    [:ethercat, :bus, :submission, :expired],
    [:ethercat, :bus, :dispatch, :sent],
    [:ethercat, :bus, :frame, :sent],
    [:ethercat, :bus, :frame, :received],
    [:ethercat, :bus, :frame, :dropped],
    [:ethercat, :bus, :frame, :ignored],
    [:ethercat, :bus, :link, :down],
    [:ethercat, :bus, :link, :reconnected],
    [:ethercat, :dc, :tick],
    [:ethercat, :dc, :sync_diff, :observed],
    [:ethercat, :dc, :lock, :changed],
    [:ethercat, :domain, :cycle, :done],
    [:ethercat, :domain, :cycle, :missed],
    [:ethercat, :domain, :stopped],
    [:ethercat, :domain, :crashed],
    [:ethercat, :slave, :crashed],
    [:ethercat, :slave, :health, :fault],
    [:ethercat, :slave, :down]
  ]

  @spec telemetry_group_options() :: [map()]
  def telemetry_group_options do
    [
      %{id: "bus", label: "Bus"},
      %{id: "dc", label: "Distributed Clocks"},
      %{id: "domain", label: "Domains"},
      %{id: "slave", label: "Slaves"}
    ]
  end

  @spec run(Scenario.t(), Run.options(), keyword(), (term() -> term())) :: Report.t()
  def run(%Scenario{} = scenario, options, opts \\ [], notify) when is_function(notify, 1) do
    runtime = build_runtime(Keyword.get(opts, :runtime, %{}))
    started_at_ms = runtime_clock_ms(runtime)
    started_mono_ms = runtime_monotonic_ms(runtime)

    notify.({:run_started, %{started_at_ms: started_at_ms, options: options}})

    {handler_id, telemetry_agent} = maybe_attach_telemetry(options, notify)

    try do
      {step_results, failure} =
        scenario.steps
        |> Enum.with_index()
        |> Enum.reduce_while({[], nil}, fn {step, index}, {results, _failure} ->
          notify.({:step_started, %{index: index, title: step.title}})
          result = execute_step(step, index, runtime)
          notify.({:step_finished, result})

          case result.status do
            :passed ->
              {:cont, {[result | results], nil}}

            :failed ->
              {:halt, {[result | results], result.detail}}
          end
        end)
        |> then(fn {results, failure} -> {Enum.reverse(results), failure} end)

      finished_at_ms = runtime_clock_ms(runtime)
      finished_mono_ms = runtime_monotonic_ms(runtime)

      report = %Report{
        scenario_name: scenario.name,
        status: if(is_nil(failure), do: :passed, else: :failed),
        started_at_ms: started_at_ms,
        finished_at_ms: finished_at_ms,
        duration_ms: max(finished_mono_ms - started_mono_ms, 0),
        step_results: step_results,
        telemetry_events: telemetry_events(telemetry_agent),
        options: options,
        failure: failure
      }

      notify.({:run_finished, report})
      report
    after
      maybe_detach_telemetry(handler_id, telemetry_agent)
    end
  end

  defp execute_step(%Step{} = step, index, runtime) do
    started_at_ms = runtime_clock_ms(runtime)
    started_mono_ms = runtime_monotonic_ms(runtime)

    base = %{
      index: index,
      title: step.title,
      kind: step.kind,
      started_at_ms: started_at_ms,
      observations: [],
      status: nil,
      detail: nil
    }

    result =
      case step.kind do
        :wait ->
          runtime.sleep.(step.params.duration_ms)
          %{base | status: :passed, detail: "waited #{step.params.duration_ms} ms"}

        :manual ->
          case runtime.manual_gate.(step, base) do
            :ok ->
              %{base | status: :passed, detail: step.params.acknowledged_detail}

            {:ok, detail} ->
              %{base | status: :passed, detail: detail}

            {:error, reason} ->
              %{base | status: :failed, detail: format_reason(reason)}

            other ->
              %{base | status: :failed, detail: "unexpected manual result #{inspect(other)}"}
          end

        :write_output ->
          case runtime.write_output.(step.params.slave, step.params.signal, step.params.value) do
            :ok ->
              %{base | status: :passed, detail: "wrote #{inspect(step.params.value)}"}

            {:error, reason} ->
              %{base | status: :failed, detail: format_reason(reason)}

            other ->
              %{base | status: :failed, detail: "unexpected write result #{inspect(other)}"}
          end

        :expect_input ->
          observe_until(
            base,
            step.params.within_ms,
            step.params.poll_ms,
            runtime,
            fn ->
              runtime.read_input.(step.params.slave, step.params.signal)
            end,
            fn
              {:ok, value} -> value == step.params.expected
              value -> value == step.params.expected
            end,
            fn value -> "expected #{inspect(step.params.expected)}, got #{inspect(value)}" end
          )

        :expect_slave_state ->
          observe_until(
            base,
            step.params.within_ms,
            step.params.poll_ms,
            runtime,
            fn ->
              case runtime.slave_info.(step.params.slave) do
                {:ok, info} -> {:ok, Map.get(info, :al_state, :unknown)}
                other -> other
              end
            end,
            fn
              {:ok, value} -> value == step.params.expected_state
              value -> value == step.params.expected_state
            end,
            fn value ->
              "expected #{inspect(step.params.expected_state)}, got #{inspect(value)}"
            end
          )

        :stop_domain_cycling ->
          case runtime.stop_domain_cycling.(step.params.domain_id) do
            :ok ->
              %{base | status: :passed, detail: "stopped #{inspect(step.params.domain_id)}"}

            {:error, reason} ->
              %{base | status: :failed, detail: format_reason(reason)}

            other ->
              %{base | status: :failed, detail: "unexpected stop result #{inspect(other)}"}
          end

        :start_domain_cycling ->
          case runtime.start_domain_cycling.(step.params.domain_id) do
            :ok ->
              %{base | status: :passed, detail: "started #{inspect(step.params.domain_id)}"}

            {:error, reason} ->
              %{base | status: :failed, detail: format_reason(reason)}

            other ->
              %{base | status: :failed, detail: "unexpected start result #{inspect(other)}"}
          end

        :expect_dc_lock ->
          observe_until(
            base,
            step.params.within_ms,
            step.params.poll_ms,
            runtime,
            fn ->
              case runtime.dc_status.() do
                {:ok, status} -> {:ok, Map.get(status, :lock_state, :unknown)}
                status when is_map(status) -> Map.get(status, :lock_state, :unknown)
                status -> status
              end
            end,
            fn
              {:ok, value} -> value == step.params.expected_state
              value -> value == step.params.expected_state
            end,
            fn value ->
              "expected #{inspect(step.params.expected_state)}, got #{inspect(value)}"
            end
          )
      end

    finished_at_ms = runtime_clock_ms(runtime)
    finished_mono_ms = runtime_monotonic_ms(runtime)

    result
    |> Map.put(:finished_at_ms, finished_at_ms)
    |> Map.put(:duration_ms, max(finished_mono_ms - started_mono_ms, 0))
  end

  defp observe_until(base, within_ms, poll_ms, runtime, fetch, predicate, detail_fun) do
    deadline_ms = runtime_monotonic_ms(runtime) + within_ms
    do_observe(base, deadline_ms, max(poll_ms, 0), runtime, fetch, predicate, detail_fun)
  end

  defp do_observe(base, deadline_ms, poll_ms, runtime, fetch, predicate, detail_fun) do
    value = fetch.()
    observed_at_ms = runtime_clock_ms(runtime)
    observed_mono_ms = runtime_monotonic_ms(runtime)

    observation = %{at_ms: observed_at_ms, value: inspect(value, pretty: false, limit: 20)}
    observations = Enum.take(base.observations ++ [observation], -10)

    cond do
      predicate.(value) ->
        %{base | status: :passed, detail: nil, observations: observations}

      observed_mono_ms >= deadline_ms ->
        %{base | status: :failed, detail: detail_fun.(value), observations: observations}

      true ->
        runtime.sleep.(poll_ms)

        base
        |> Map.put(:observations, observations)
        |> do_observe(deadline_ms, poll_ms, runtime, fetch, predicate, detail_fun)
    end
  end

  defp build_runtime(overrides) when is_map(overrides) do
    Map.merge(default_runtime(), overrides)
  end

  defp default_runtime do
    %{
      now_ms: fn -> System.system_time(:millisecond) end,
      clock_ms: fn -> System.system_time(:millisecond) end,
      monotonic_ms: fn -> System.monotonic_time(:millisecond) end,
      sleep: fn ms -> Process.sleep(ms) end,
      write_output: &EtherCAT.write_output/3,
      read_input: &EtherCAT.read_input/2,
      slave_info: &EtherCAT.slave_info/1,
      stop_domain_cycling: &EtherCAT.Domain.stop_cycling/1,
      start_domain_cycling: &EtherCAT.Domain.start_cycling/1,
      dc_status: &EtherCAT.dc_status/0,
      manual_gate: fn _step, _base ->
        {:error, :manual_step_requires_interactive_runner}
      end
    }
  end

  defp maybe_attach_telemetry(%{attach_telemetry?: false}, _notify), do: {nil, nil}
  defp maybe_attach_telemetry(%{telemetry_groups: []}, _notify), do: {nil, nil}

  defp maybe_attach_telemetry(options, notify) do
    events = telemetry_events_for(options.telemetry_groups)
    handler_id = "kino-ethercat-testing-#{System.unique_integer([:positive, :monotonic])}"
    {:ok, agent} = Agent.start_link(fn -> [] end)

    :ok =
      :telemetry.attach_many(
        handler_id,
        events,
        &__MODULE__.handle_telemetry_event/4,
        {notify, agent}
      )

    {handler_id, agent}
  end

  defp maybe_detach_telemetry(nil, nil), do: :ok

  defp maybe_detach_telemetry(handler_id, telemetry_agent) do
    :telemetry.detach(handler_id)
    Agent.stop(telemetry_agent)
    :ok
  end

  defp telemetry_events(nil), do: []
  defp telemetry_events(agent), do: agent |> Agent.get(&Enum.reverse(&1))

  defp normalize_telemetry_event(event, measurements, metadata) do
    %{
      id: System.unique_integer([:positive, :monotonic]),
      at_ms: System.system_time(:millisecond),
      group: telemetry_group(event),
      event: Enum.map_join(event, ".", &to_string/1),
      detail: telemetry_detail(measurements, metadata)
    }
  end

  defp telemetry_group([:ethercat, group | _rest]), do: group
  defp telemetry_group(_event), do: :other

  defp telemetry_detail(measurements, metadata) do
    [measurements, metadata]
    |> Enum.reject(&(&1 == %{}))
    |> Enum.map_join(" | ", &inspect(&1, pretty: false, limit: 10))
  end

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)

  @doc false
  def handle_telemetry_event(event, measurements, metadata, {notify, agent}) do
    entry = normalize_telemetry_event(event, measurements, metadata)
    Agent.update(agent, fn entries -> [entry | entries] |> Enum.take(100) end)
    notify.({:telemetry_event, entry})
  end

  defp runtime_clock_ms(runtime) do
    runtime
    |> Map.get(:clock_ms, Map.fetch!(runtime, :now_ms))
    |> then(& &1.())
  end

  defp runtime_monotonic_ms(runtime) do
    runtime
    |> Map.get(:monotonic_ms, Map.fetch!(runtime, :now_ms))
    |> then(& &1.())
  end

  defp telemetry_events_for(groups) do
    groups = Enum.filter(groups, &(&1 in @telemetry_groups))

    available_telemetry_events()
    |> Enum.filter(fn
      [:ethercat, group | _rest] -> group in groups
      _event -> false
    end)
  end

  defp available_telemetry_events do
    if Code.ensure_loaded?(EtherCAT.Telemetry) and
         function_exported?(EtherCAT.Telemetry, :events, 0) do
      apply(EtherCAT.Telemetry, :events, [])
    else
      @fallback_telemetry_events
    end
  end
end
