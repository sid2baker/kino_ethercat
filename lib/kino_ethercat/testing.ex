defmodule KinoEtherCAT.Testing do
  @moduledoc """
  Scenario-based EtherCAT validation and diagnostics.

  Build scenarios from reusable steps, then create a renderable run handle:

      scenario =
        KinoEtherCAT.Testing.scenario("Digital loopback")
        |> KinoEtherCAT.Testing.add_step(
          KinoEtherCAT.Testing.write_output("Drive Q1 high", :el2809, :q1, 1)
        )
        |> KinoEtherCAT.Testing.add_step(
          KinoEtherCAT.Testing.expect_input("Observe I1", :el1809, :i1, 1, within_ms: 100)
        )

      KinoEtherCAT.Testing.new(scenario)

  The returned `%KinoEtherCAT.Testing.Run{}` implements `Kino.Render`.
  """

  alias KinoEtherCAT.Testing.{Run, Scenario, Step}

  @spec scenario(String.t(), keyword()) :: Scenario.t()
  def scenario(name, opts \\ []), do: Scenario.new(name, opts)

  @spec add_step(Scenario.t(), Step.t()) :: Scenario.t()
  def add_step(%Scenario{} = scenario, %Step{} = step), do: Scenario.add_step(scenario, step)

  @spec wait(String.t(), non_neg_integer(), keyword()) :: Step.t()
  def wait(title, duration_ms, opts \\ []), do: Step.wait(title, duration_ms, opts)

  @spec write_output(String.t(), atom(), atom(), term(), keyword()) :: Step.t()
  def write_output(title, slave, signal, value, opts \\ []) do
    Step.write_output(title, slave, signal, value, opts)
  end

  @spec expect_input(String.t(), atom(), atom(), term(), keyword()) :: Step.t()
  def expect_input(title, slave, signal, expected, opts \\ []) do
    Step.expect_input(title, slave, signal, expected, opts)
  end

  @spec expect_slave_state(String.t(), atom(), atom(), keyword()) :: Step.t()
  def expect_slave_state(title, slave, expected_state, opts \\ []) do
    Step.expect_slave_state(title, slave, expected_state, opts)
  end

  @spec new(Scenario.t(), keyword()) :: Run.t()
  def new(%Scenario{} = scenario, opts \\ []) do
    %Run{
      scenario: scenario,
      options: Run.normalize_options(opts)
    }
  end
end
