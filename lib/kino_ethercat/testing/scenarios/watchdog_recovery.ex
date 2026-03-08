defmodule KinoEtherCAT.Testing.Scenarios.WatchdogRecovery do
  @moduledoc """
  A watchdog trip and recovery validation derived from `watchdog_recovery.exs`.

  The scenario primes the selected loopback channels high, stops the domain to trigger
  the EL2809 safe state, verifies the outputs fall low through the loopback, then
  restarts the domain and confirms the slave returns to OP and the loopback recovers.
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
    domain_id = Keyword.get(opts, :domain_id, :main)
    output_slave = Keyword.get(opts, :output_slave, :outputs)
    input_slave = Keyword.get(opts, :input_slave, :inputs)
    watchdog_slave = Keyword.get(opts, :watchdog_slave, output_slave)
    pairs = Keyword.get(opts, :pairs, @default_pairs)
    settle_ms = Keyword.get(opts, :settle_ms, 250)
    trip_timeout_ms = Keyword.get(opts, :trip_timeout_ms, 2_000)
    recover_timeout_ms = Keyword.get(opts, :recover_timeout_ms, 5_000)
    timeout_ms = Keyword.get(opts, :timeout_ms, trip_timeout_ms + recover_timeout_ms + 10_000)

    Testing.scenario("Watchdog recovery",
      description:
        "Stop domain cycling to trip the output watchdog, confirm safe-state loopback, then restart cycling and verify recovery.",
      timeout_ms: timeout_ms,
      tags: ["validation", "watchdog", "recovery"]
    )
    |> Testing.add_step(
      Testing.expect_slave_state(
        "Confirm #{inspect(watchdog_slave)} is operational",
        watchdog_slave,
        :op,
        within_ms: recover_timeout_ms
      )
    )
    |> drive_pairs_high(output_slave, input_slave, pairs, settle_ms)
    |> Testing.add_step(
      Testing.stop_domain_cycling("Stop domain #{inspect(domain_id)}", domain_id)
    )
    |> Testing.add_step(
      Testing.expect_slave_state(
        "Wait for #{inspect(watchdog_slave)} watchdog trip",
        watchdog_slave,
        :safeop,
        within_ms: trip_timeout_ms
      )
    )
    |> expect_pairs_low(input_slave, pairs, settle_ms)
    |> Testing.add_step(
      Testing.start_domain_cycling("Restart domain #{inspect(domain_id)}", domain_id)
    )
    |> Testing.add_step(
      Testing.expect_slave_state(
        "Wait for #{inspect(watchdog_slave)} to recover",
        watchdog_slave,
        :op,
        within_ms: recover_timeout_ms
      )
    )
    |> drive_pairs_high(output_slave, input_slave, pairs, settle_ms)
    |> drive_pairs_low(output_slave, input_slave, pairs, settle_ms)
  end

  defp drive_pairs_high(scenario, output_slave, input_slave, pairs, settle_ms) do
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
    end)
  end

  defp drive_pairs_low(scenario, output_slave, input_slave, pairs, settle_ms) do
    Enum.reduce(pairs, scenario, fn {output_signal, input_signal}, current ->
      label = "#{output_signal} -> #{input_signal}"

      current
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

  defp expect_pairs_low(scenario, input_slave, pairs, settle_ms) do
    Enum.reduce(pairs, scenario, fn {_output_signal, input_signal}, current ->
      Testing.add_step(
        current,
        Testing.expect_input(
          "Confirm #{input_signal} fell to safe state",
          input_slave,
          input_signal,
          0,
          within_ms: settle_ms
        )
      )
    end)
  end
end
