defmodule KinoEtherCAT.TestingTest do
  use ExUnit.Case, async: true

  alias KinoEtherCAT.Testing
  alias KinoEtherCAT.Testing.{Run, Runner}
  alias KinoEtherCAT.Testing.Scenarios

  setup_all do
    Application.ensure_all_started(:telemetry)
    Application.ensure_all_started(:kino)
    :ok
  end

  test "new returns a renderable run handle with normalized options" do
    scenario =
      Testing.scenario("Loopback",
        description: "Drive one output and observe one input",
        tags: ["io"]
      )

    run =
      Testing.new(scenario,
        attach_telemetry: true,
        telemetry_groups: [:bus, "dc", :unknown]
      )

    assert %Run{} = run

    assert run.options == %{
             attach_telemetry?: true,
             telemetry_groups: [:bus, :dc]
           }

    assert %{type: :js, js_view: %{pid: pid}} = Kino.Render.to_livebook(run)
    assert is_pid(pid)
  end

  test "runner executes steps and captures selected telemetry events" do
    {:ok, runtime_state} =
      Agent.start_link(fn ->
        %{
          clock_ms: 1_710_000_000_000,
          monotonic_ms: 0,
          input_reads: [0, 1],
          writes: []
        }
      end)

    on_exit(fn ->
      if Process.alive?(runtime_state), do: Agent.stop(runtime_state)
    end)

    scenario =
      Testing.scenario("Loopback", description: "Drive and observe")
      |> Testing.add_step(Testing.write_output("Drive Q1", :rack_out, :q1, 1))
      |> Testing.add_step(
        Testing.expect_input("Observe I1", :rack_in, :i1, 1, within_ms: 50, poll_ms: 10)
      )

    report =
      Runner.run(
        scenario,
        Run.normalize_options(attach_telemetry: true, telemetry_groups: [:bus]),
        [runtime: fake_runtime(runtime_state, emit_bus_event?: true)],
        fn _event -> :ok end
      )

    assert report.status == :passed
    assert report.duration_ms == 10
    assert Enum.all?(report.step_results, &(&1.status == :passed))
    assert [%{group: :bus, event: "ethercat.bus.link.down"}] = report.telemetry_events

    assert Agent.get(runtime_state, &Enum.reverse(&1.writes)) == [
             {:rack_out, :q1, 1}
           ]
  end

  test "runner stops on the first failed expectation" do
    {:ok, runtime_state} =
      Agent.start_link(fn ->
        %{
          clock_ms: 1_710_000_100_000,
          monotonic_ms: 0,
          input_reads: [0, 0, 0],
          writes: []
        }
      end)

    on_exit(fn ->
      if Process.alive?(runtime_state), do: Agent.stop(runtime_state)
    end)

    scenario =
      Testing.scenario("Failure case")
      |> Testing.add_step(
        Testing.expect_input("Observe I1", :rack_in, :i1, 1, within_ms: 20, poll_ms: 10)
      )
      |> Testing.add_step(Testing.wait("Should not run", 5))

    report =
      Runner.run(
        scenario,
        Run.normalize_options([]),
        [runtime: fake_runtime(runtime_state)],
        fn _event -> :ok end
      )

    assert report.status == :failed
    assert report.failure == "expected 1, got 0"
    assert [%{status: :failed, title: "Observe I1"}] = report.step_results
  end

  test "runner supports domain control and dc lock steps" do
    {:ok, runtime_state} =
      Agent.start_link(fn ->
        %{
          clock_ms: 1_710_000_200_000,
          monotonic_ms: 0,
          input_reads: [],
          writes: [],
          domain_actions: [],
          dc_states: [:locking, :locked]
        }
      end)

    on_exit(fn ->
      if Process.alive?(runtime_state), do: Agent.stop(runtime_state)
    end)

    scenario =
      Testing.scenario("Domain controls")
      |> Testing.add_step(Testing.stop_domain_cycling("Stop main", :main))
      |> Testing.add_step(Testing.start_domain_cycling("Start main", :main))
      |> Testing.add_step(
        Testing.expect_dc_lock("Wait for lock", :locked, within_ms: 20, poll_ms: 10)
      )

    report =
      Runner.run(
        scenario,
        Run.normalize_options([]),
        [runtime: fake_runtime(runtime_state)],
        fn _event -> :ok end
      )

    assert report.status == :passed

    assert Enum.map(report.step_results, & &1.kind) == [
             :stop_domain_cycling,
             :start_domain_cycling,
             :expect_dc_lock
           ]

    assert Agent.get(runtime_state, &Enum.reverse(&1.domain_actions)) == [
             {:stop, :main},
             {:start, :main}
           ]
  end

  test "built in loopback smoke scenario models paired IO validation" do
    scenario =
      Scenarios.loopback_smoke(
        pairs: [{:ch1, :ch1}, {:ch5, :ch5}],
        settle_ms: 150
      )

    assert scenario.name == "Loopback smoke"
    assert scenario.tags == ["validation", "loopback", "digital-io"]

    assert Enum.map(scenario.steps, & &1.kind) == [
             :write_output,
             :expect_input,
             :write_output,
             :expect_input,
             :write_output,
             :expect_input,
             :write_output,
             :expect_input
           ]

    assert [
             %{params: %{signal: :ch1, value: 1}},
             %{params: %{expected: 1, signal: :ch1, within_ms: 150}},
             %{params: %{signal: :ch1, value: 0}},
             %{params: %{expected: 0, signal: :ch1, within_ms: 150}}
             | _
           ] = scenario.steps
  end

  test "built in watchdog recovery scenario includes watchdog trip and recovery phases" do
    scenario = Scenarios.watchdog_recovery(pairs: [{:ch1, :ch1}])

    assert scenario.name == "Watchdog recovery"

    assert Enum.map(scenario.steps, & &1.kind) == [
             :expect_slave_state,
             :write_output,
             :expect_input,
             :stop_domain_cycling,
             :expect_slave_state,
             :expect_input,
             :start_domain_cycling,
             :expect_slave_state,
             :write_output,
             :expect_input,
             :write_output,
             :expect_input
           ]
  end

  test "built in dc lock scenario checks slave op state before lock convergence" do
    scenario = Scenarios.dc_lock(slaves: [:coupler, :outputs], within_ms: 2_000)

    assert scenario.name == "DC lock"

    assert Enum.map(scenario.steps, & &1.kind) == [
             :expect_slave_state,
             :expect_slave_state,
             :expect_dc_lock
           ]

    assert List.last(scenario.steps) == %{
             List.last(scenario.steps)
             | kind: :expect_dc_lock,
               params: %{expected_state: :locked, within_ms: 2_000, poll_ms: 50}
           }
  end

  defp fake_runtime(runtime_state, opts \\ []) do
    emit_bus_event? = Keyword.get(opts, :emit_bus_event?, false)

    %{
      clock_ms: fn -> Agent.get(runtime_state, & &1.clock_ms) end,
      monotonic_ms: fn -> Agent.get(runtime_state, & &1.monotonic_ms) end,
      sleep: fn duration_ms ->
        Agent.update(runtime_state, fn state ->
          %{
            state
            | clock_ms: state.clock_ms + duration_ms,
              monotonic_ms: state.monotonic_ms + duration_ms
          }
        end)
      end,
      write_output: fn slave, signal, value ->
        if emit_bus_event? do
          :telemetry.execute(
            [:ethercat, :bus, :link, :down],
            %{},
            %{link: "eth0", reason: {:test, slave, signal, value}}
          )
        end

        Agent.update(runtime_state, fn state ->
          %{state | writes: [{slave, signal, value} | state.writes]}
        end)

        :ok
      end,
      read_input: fn _slave, _signal ->
        Agent.get_and_update(runtime_state, fn state ->
          case state.input_reads do
            [value | rest] -> {value, %{state | input_reads: rest}}
            [] -> {0, state}
          end
        end)
      end,
      slave_info: fn slave -> {:ok, %{name: slave, al_state: :op}} end,
      stop_domain_cycling: fn domain_id ->
        Agent.update(runtime_state, fn state ->
          %{state | domain_actions: [{:stop, domain_id} | Map.get(state, :domain_actions, [])]}
        end)

        :ok
      end,
      start_domain_cycling: fn domain_id ->
        Agent.update(runtime_state, fn state ->
          %{state | domain_actions: [{:start, domain_id} | Map.get(state, :domain_actions, [])]}
        end)

        :ok
      end,
      dc_status: fn ->
        Agent.get_and_update(runtime_state, fn state ->
          case Map.get(state, :dc_states, [:locked]) do
            [value | rest] -> {%{lock_state: value}, %{state | dc_states: rest}}
            [] -> {%{lock_state: :locked}, state}
          end
        end)
      end
    }
  end
end
