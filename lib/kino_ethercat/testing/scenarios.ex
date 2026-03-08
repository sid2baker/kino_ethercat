defmodule KinoEtherCAT.Testing.Scenarios do
  @moduledoc """
  Built-in EtherCAT validation scenarios derived from the maintained example flows.
  """

  alias KinoEtherCAT.Testing.Scenarios.{DCLock, LoopbackSmoke, WatchdogRecovery}

  @spec loopback_smoke(keyword()) :: KinoEtherCAT.Testing.Scenario.t()
  def loopback_smoke(opts \\ []), do: LoopbackSmoke.new(opts)

  @spec dc_lock(keyword()) :: KinoEtherCAT.Testing.Scenario.t()
  def dc_lock(opts \\ []), do: DCLock.new(opts)

  @spec watchdog_recovery(keyword()) :: KinoEtherCAT.Testing.Scenario.t()
  def watchdog_recovery(opts \\ []), do: WatchdogRecovery.new(opts)
end
