defmodule KinoEtherCAT.Testing.Panel do
  @moduledoc false

  use Kino.JS, assets_path: "lib/assets/testing/build"
  use Kino.JS.Live

  alias KinoEtherCAT.Testing.{Report, Run, Runner}

  @flush_ms 200

  @spec new(Run.t()) :: Kino.JS.Live.t()
  def new(%Run{} = run) do
    Kino.JS.Live.new(__MODULE__, run)
  end

  @impl true
  def init(%Run{} = run, ctx) do
    state = %{
      run: run,
      status: :idle,
      current_step: nil,
      started_at_ms: nil,
      finished_at_ms: nil,
      duration_ms: nil,
      failure: nil,
      step_results: %{},
      telemetry_events: [],
      options: run.options,
      execution_ref: nil,
      runner_pid: nil,
      manual_prompt: nil
    }

    {:ok,
     assign(ctx,
       state: state,
       payload: payload(state),
       flush_scheduled?: false
     )}
  end

  @impl true
  def handle_connect(ctx) do
    {:ok, ctx.assigns.payload, ctx}
  end

  @impl true
  def handle_event("update_options", params, ctx) do
    options =
      Run.normalize_options(%{
        attach_telemetry: Map.get(params, "attach_telemetry", false),
        telemetry_groups: List.wrap(Map.get(params, "telemetry_groups", []))
      })

    state = put_in(ctx.assigns.state.options, options)
    ctx = assign(ctx, state: state) |> schedule_flush()
    {:noreply, ctx}
  end

  def handle_event("run", _params, %{assigns: %{state: %{status: status}}} = ctx)
      when status in [:running, :awaiting_input],
      do: {:noreply, ctx}

  def handle_event("run", _params, ctx) do
    execution_ref = System.unique_integer([:positive, :monotonic])

    state =
      ctx.assigns.state
      |> Map.put(:status, :running)
      |> Map.put(:current_step, nil)
      |> Map.put(:started_at_ms, System.system_time(:millisecond))
      |> Map.put(:finished_at_ms, nil)
      |> Map.put(:duration_ms, nil)
      |> Map.put(:failure, nil)
      |> Map.put(:step_results, %{})
      |> Map.put(:telemetry_events, [])
      |> Map.put(:runner_pid, nil)
      |> Map.put(:manual_prompt, nil)
      |> Map.put(:execution_ref, execution_ref)

    server = self()
    run = state.run
    options = state.options

    {:ok, runner_pid} =
      Task.start(fn ->
        try do
          Runner.run(
            run.scenario,
            options,
            [runtime: runtime_overrides(execution_ref, server)],
            fn event ->
              send(server, {:runner_event, execution_ref, event})
            end
          )
        rescue
          exception ->
            send(
              server,
              {:runner_event, execution_ref, {:run_crashed, Exception.message(exception)}}
            )
        catch
          kind, reason ->
            send(
              server,
              {:runner_event, execution_ref,
               {:run_crashed, Exception.format(kind, reason, __STACKTRACE__)}}
            )
        end
      end)

    state = Map.put(state, :runner_pid, runner_pid)

    ctx = assign(ctx, state: state) |> schedule_flush()
    {:noreply, ctx}
  end

  def handle_event("continue", _params, %{assigns: %{state: %{status: :awaiting_input}}} = ctx) do
    case ctx.assigns.state do
      %{runner_pid: runner_pid, execution_ref: execution_ref, current_step: current_step}
      when is_pid(runner_pid) and is_integer(current_step) ->
        send(runner_pid, {:manual_continue, execution_ref, current_step})

        state =
          ctx.assigns.state
          |> Map.put(:status, :running)
          |> Map.put(:manual_prompt, nil)

        {:noreply, assign(ctx, state: state) |> schedule_flush()}

      _state ->
        {:noreply, ctx}
    end
  end

  def handle_event("continue", _params, ctx), do: {:noreply, ctx}

  def handle_event("reset", _params, ctx) do
    maybe_stop_runner(ctx.assigns.state.runner_pid)

    state =
      ctx.assigns.state
      |> Map.put(:status, :idle)
      |> Map.put(:current_step, nil)
      |> Map.put(:started_at_ms, nil)
      |> Map.put(:finished_at_ms, nil)
      |> Map.put(:duration_ms, nil)
      |> Map.put(:failure, nil)
      |> Map.put(:step_results, %{})
      |> Map.put(:telemetry_events, [])
      |> Map.put(:runner_pid, nil)
      |> Map.put(:manual_prompt, nil)
      |> Map.put(:execution_ref, nil)

    ctx = assign(ctx, state: state) |> schedule_flush()
    {:noreply, ctx}
  end

  @impl true
  def handle_info({:runner_event, execution_ref, event}, ctx) do
    if ctx.assigns.state.execution_ref == execution_ref do
      handle_runner_event(event, ctx)
    else
      {:noreply, ctx}
    end
  end

  def handle_info(:flush, ctx) do
    payload = payload(ctx.assigns.state)
    broadcast_event(ctx, "snapshot", payload)
    {:noreply, assign(ctx, payload: payload, flush_scheduled?: false)}
  end

  defp handle_runner_event({:run_started, %{started_at_ms: started_at_ms}}, ctx) do
    state =
      ctx.assigns.state
      |> Map.put(:status, :running)
      |> Map.put(:started_at_ms, started_at_ms)

    {:noreply, assign(ctx, state: state) |> schedule_flush()}
  end

  defp handle_runner_event({:step_started, %{index: index}}, ctx) do
    state = Map.put(ctx.assigns.state, :current_step, index)
    {:noreply, assign(ctx, state: state) |> schedule_flush()}
  end

  defp handle_runner_event({:step_finished, step_result}, ctx) do
    state =
      ctx.assigns.state
      |> put_in([:step_results, step_result.index], step_result)
      |> Map.put(:current_step, nil)

    {:noreply, assign(ctx, state: state) |> schedule_flush()}
  end

  defp handle_runner_event({:manual_waiting, prompt}, ctx) do
    state =
      ctx.assigns.state
      |> Map.put(:status, :awaiting_input)
      |> Map.put(:current_step, prompt.index)
      |> Map.put(:manual_prompt, prompt)
      |> put_in([:step_results, prompt.index], %{
        index: prompt.index,
        title: prompt.title,
        kind: :manual,
        status: :awaiting_input,
        started_at_ms: prompt.started_at_ms,
        finished_at_ms: nil,
        duration_ms: nil,
        detail: prompt.instruction,
        observations: []
      })

    {:noreply, assign(ctx, state: state) |> schedule_flush()}
  end

  defp handle_runner_event({:telemetry_event, entry}, ctx) do
    state =
      update_in(ctx.assigns.state.telemetry_events, fn entries ->
        [entry | entries] |> Enum.take(80)
      end)

    {:noreply, assign(ctx, state: state) |> schedule_flush()}
  end

  defp handle_runner_event({:run_finished, %Report{} = report}, ctx) do
    step_results = Map.new(report.step_results, &{&1.index, &1})

    state =
      ctx.assigns.state
      |> Map.put(:status, report.status)
      |> Map.put(:current_step, nil)
      |> Map.put(:finished_at_ms, report.finished_at_ms)
      |> Map.put(:duration_ms, report.duration_ms)
      |> Map.put(:failure, report.failure)
      |> Map.put(:step_results, step_results)
      |> Map.put(:telemetry_events, Enum.reverse(report.telemetry_events))
      |> Map.put(:runner_pid, nil)
      |> Map.put(:manual_prompt, nil)
      |> Map.put(:execution_ref, nil)

    {:noreply, assign(ctx, state: state) |> schedule_flush()}
  end

  defp handle_runner_event({:run_crashed, detail}, ctx) do
    now_ms = System.system_time(:millisecond)

    state =
      ctx.assigns.state
      |> Map.put(:status, :failed)
      |> Map.put(:current_step, nil)
      |> Map.put(:finished_at_ms, now_ms)
      |> Map.put(:duration_ms, duration(ctx.assigns.state.started_at_ms, now_ms))
      |> Map.put(:failure, detail)
      |> Map.put(:runner_pid, nil)
      |> Map.put(:manual_prompt, nil)
      |> Map.put(:execution_ref, nil)

    {:noreply, assign(ctx, state: state) |> schedule_flush()}
  end

  defp schedule_flush(%{assigns: %{flush_scheduled?: true}} = ctx), do: ctx

  defp schedule_flush(ctx) do
    Process.send_after(self(), :flush, @flush_ms)
    assign(ctx, flush_scheduled?: true)
  end

  defp payload(state) do
    scenario = state.run.scenario

    %{
      title: scenario.name,
      description: scenario.description,
      tags: scenario.tags,
      timeout_ms: scenario.timeout_ms,
      status: to_string(state.status),
      started_at_ms: state.started_at_ms,
      finished_at_ms: state.finished_at_ms,
      duration_ms: state.duration_ms,
      failure: state.failure,
      running: state.status == :running,
      busy: state.status in [:running, :awaiting_input],
      current_step: state.current_step,
      manual_prompt: state.manual_prompt,
      options: %{
        attach_telemetry: state.options.attach_telemetry?,
        telemetry_groups: Enum.map(state.options.telemetry_groups, &Atom.to_string/1),
        available_groups: Runner.telemetry_group_options()
      },
      steps:
        scenario.steps
        |> Enum.with_index()
        |> Enum.map(fn {step, index} ->
          step_result = Map.get(state.step_results, index)

          %{
            index: index,
            title: step.title,
            kind: to_string(step.kind),
            status: step_status(step_result, state.current_step, index, state.status),
            detail: step_result && step_result.detail,
            duration_ms: step_result && step_result.duration_ms,
            observations: (step_result && step_result.observations) || []
          }
        end),
      telemetry_events: state.telemetry_events
    }
  end

  defp step_status(nil, current_step, index, :running) when current_step == index, do: "running"

  defp step_status(nil, current_step, index, :awaiting_input) when current_step == index,
    do: "awaiting_input"

  defp step_status(nil, _current_step, _index, _run_status), do: "pending"

  defp step_status(step_result, _current_step, _index, _run_status),
    do: to_string(step_result.status)

  defp duration(nil, _finished_at_ms), do: nil
  defp duration(started_at_ms, finished_at_ms), do: max(finished_at_ms - started_at_ms, 0)

  defp maybe_stop_runner(pid) when is_pid(pid), do: Process.exit(pid, :kill)
  defp maybe_stop_runner(_pid), do: :ok

  defp runtime_overrides(execution_ref, server) do
    %{
      manual_gate: fn step, base ->
        index = base.index
        send(server, {:runner_event, execution_ref, {:manual_waiting, manual_prompt(step, base)}})

        receive do
          {:manual_continue, ^execution_ref, ^index} ->
            {:ok, step.params.acknowledged_detail}
        after
          86_400_000 ->
            {:error, :manual_step_timeout}
        end
      end
    }
  end

  defp manual_prompt(step, base) do
    %{
      index: base.index,
      title: step.title,
      instruction: step.params.instruction,
      continue_label: step.params.continue_label,
      started_at_ms: base.started_at_ms
    }
  end
end
