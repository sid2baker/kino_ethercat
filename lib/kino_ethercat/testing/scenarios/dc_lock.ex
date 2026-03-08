defmodule KinoEtherCAT.Testing.Scenarios.DCLock do
  @moduledoc """
  A DC lock convergence validation distilled from the `dc_sync.exs` example.

  This scenario assumes the bus is already configured with DC enabled and checks that
  the named slaves are operational before waiting for the distributed clocks runtime to
  report the target lock state.
  """

  alias KinoEtherCAT.Testing

  @default_slaves [:coupler, :inputs, :outputs]

  @spec new(keyword()) :: KinoEtherCAT.Testing.Scenario.t()
  def new(opts \\ []) do
    slaves = Keyword.get(opts, :slaves, @default_slaves)
    expected_lock_state = Keyword.get(opts, :expected_lock_state, :locked)
    within_ms = Keyword.get(opts, :within_ms, 10_000)
    poll_ms = Keyword.get(opts, :poll_ms, 50)
    timeout_ms = Keyword.get(opts, :timeout_ms, within_ms + 5_000)

    Testing.scenario("DC lock",
      description:
        "Confirm the configured slaves are operational and the distributed clocks runtime converges to the requested lock state.",
      timeout_ms: timeout_ms,
      tags: ["validation", "dc", "synchronization"]
    )
    |> add_slave_checks(slaves, within_ms)
    |> Testing.add_step(
      Testing.expect_dc_lock(
        "Wait for DC lock #{expected_lock_state}",
        expected_lock_state,
        within_ms: within_ms,
        poll_ms: poll_ms
      )
    )
  end

  defp add_slave_checks(scenario, slaves, within_ms) do
    Enum.reduce(slaves, scenario, fn slave, current ->
      Testing.add_step(
        current,
        Testing.expect_slave_state(
          "Confirm #{inspect(slave)} is operational",
          slave,
          :op,
          within_ms: within_ms
        )
      )
    end)
  end
end
