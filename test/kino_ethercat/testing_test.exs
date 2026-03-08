defmodule KinoEtherCAT.TestingTest do
  use ExUnit.Case, async: true

  alias KinoEtherCAT.Testing
  alias KinoEtherCAT.Testing.{Run, Runner}

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
      slave_info: fn slave -> {:ok, %{name: slave, al_state: :op}} end
    }
  end
end
