defmodule KinoEtherCAT.Testing do
  @moduledoc """
  Operator-guided EtherCAT validation and diagnostics.

  Build scenarios from reusable steps, including manual operator instructions,
  then create a renderable run handle:

      scenario =
        KinoEtherCAT.Testing.scenario("Digital loopback")
        |> KinoEtherCAT.Testing.add_step(
          KinoEtherCAT.Testing.write_output("Drive Q1 high", :el2809, :q1, 1)
        )
        |> KinoEtherCAT.Testing.add_step(
          KinoEtherCAT.Testing.expect_input("Observe I1", :el1809, :i1, 1, within_ms: 100)
        )
        |> KinoEtherCAT.Testing.add_step(
          KinoEtherCAT.Testing.manual(
            "Disconnect the slave segment",
            "Unplug the cable after :outputs, then click Continue in the UI."
          )
        )

      KinoEtherCAT.Testing.new(scenario)

  The returned `%KinoEtherCAT.Testing.Run{}` implements `Kino.Render`.

  Built-in scenarios derived from the maintained validation examples live under
  `KinoEtherCAT.Testing.Scenarios`.
  """

  alias KinoEtherCAT.Testing.{Run, Scenario, Step}

  @spec scenario(String.t(), keyword()) :: Scenario.t()
  def scenario(name, opts \\ []), do: Scenario.new(name, opts)

  @spec add_step(Scenario.t(), Step.t()) :: Scenario.t()
  def add_step(%Scenario{} = scenario, %Step{} = step), do: Scenario.add_step(scenario, step)

  @spec wait(String.t(), non_neg_integer(), keyword()) :: Step.t()
  def wait(title, duration_ms, opts \\ []), do: Step.wait(title, duration_ms, opts)

  @spec manual(String.t(), String.t(), keyword()) :: Step.t()
  def manual(title, instruction, opts \\ []) do
    Step.manual(title, instruction, opts)
  end

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

  @spec stop_domain_cycling(String.t(), atom(), keyword()) :: Step.t()
  def stop_domain_cycling(title, domain_id, opts \\ []) do
    Step.stop_domain_cycling(title, domain_id, opts)
  end

  @spec start_domain_cycling(String.t(), atom(), keyword()) :: Step.t()
  def start_domain_cycling(title, domain_id, opts \\ []) do
    Step.start_domain_cycling(title, domain_id, opts)
  end

  @spec expect_dc_lock(String.t(), atom(), keyword()) :: Step.t()
  def expect_dc_lock(title, expected_state, opts \\ []) do
    Step.expect_dc_lock(title, expected_state, opts)
  end

  @spec new(Scenario.t(), keyword()) :: Run.t()
  def new(%Scenario{} = scenario, opts \\ []) do
    %Run{
      scenario: scenario,
      options: Run.normalize_options(opts)
    }
  end
end
