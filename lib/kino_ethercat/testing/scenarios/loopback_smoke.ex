defmodule KinoEtherCAT.Testing.Scenarios.LoopbackSmoke do
  @moduledoc """
  A compact digital loopback validation derived from the loopback and jitter examples.

  The scenario drives each configured output/input pair high, confirms the reflected
  input, then drives it low again. This is the fast validation pass to run before
  timing or watchdog scenarios.
  """

  alias KinoEtherCAT.Testing

  @default_pairs [
    {:ch1, :ch1},
    {:ch2, :ch2},
    {:ch3, :ch3},
    {:ch4, :ch4}
  ]

  @spec new(keyword()) :: KinoEtherCAT.Testing.Scenario.t()
  def new(opts \\ []) do
    output_slave = Keyword.get(opts, :output_slave, :outputs)
    input_slave = Keyword.get(opts, :input_slave, :inputs)
    pairs = Keyword.get(opts, :pairs, @default_pairs)
    settle_ms = Keyword.get(opts, :settle_ms, 250)
    timeout_ms = Keyword.get(opts, :timeout_ms, 15_000)

    Testing.scenario("Loopback smoke",
      description:
        "Drive selected digital outputs high and low and confirm the expected loopback inputs.",
      timeout_ms: timeout_ms,
      tags: ["validation", "loopback", "digital-io"]
    )
    |> add_steps_for_pairs(output_slave, input_slave, pairs, settle_ms)
  end

  defp add_steps_for_pairs(scenario, output_slave, input_slave, pairs, settle_ms) do
    Enum.reduce(pairs, scenario, fn {output_signal, input_signal}, current ->
      label = "#{output_signal} -> #{input_signal}"

      current
      |> Testing.add_step(
        Testing.write_output("Drive #{label} high", output_slave, output_signal, 1)
      )
      |> Testing.add_step(
        Testing.expect_input(
          "Observe #{label} high",
          input_slave,
          input_signal,
          1,
          within_ms: settle_ms
        )
      )
      |> Testing.add_step(
        Testing.write_output("Drive #{label} low", output_slave, output_signal, 0)
      )
      |> Testing.add_step(
        Testing.expect_input(
          "Observe #{label} low",
          input_slave,
          input_signal,
          0,
          within_ms: settle_ms
        )
      )
    end)
  end
end
