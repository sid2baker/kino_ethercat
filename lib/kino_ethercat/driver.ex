defmodule KinoEtherCAT.Driver do
  @moduledoc """
  Registry of built-in EtherCAT slave drivers shipped with KinoEtherCAT.

  Use `all/0` to enumerate available drivers (e.g. for a UI dropdown) and
  `lookup/1` to resolve a slave identity map to its driver module.

  `simulator_all/0` returns the built-in drivers that also expose simulator
  hydration through a `MyDriver.Simulator` companion implementing
  `EtherCAT.Simulator.DriverAdapter`.
  """

  alias EtherCAT.Simulator.DriverAdapter
  alias EtherCAT.Slave.Driver, as: SlaveDriver

  @driver_modules [
    KinoEtherCAT.Driver.EK1100,
    KinoEtherCAT.Driver.EL1809,
    KinoEtherCAT.Driver.EL2809,
    KinoEtherCAT.Driver.EL3202
  ]

  @doc "Returns all registered drivers."
  def all do
    @driver_modules
    |> Enum.map(&entry/1)
    |> Enum.filter(& &1.assignable?)
  end

  @doc "Returns all registered drivers that expose simulator hydration."
  def simulator_all do
    @driver_modules
    |> Enum.map(&entry/1)
    |> Enum.filter(& &1.simulator?)
  end

  @doc """
  Looks up a driver by slave identity.

  Matches on `vendor_id`, `product_code`, and optional `revision`.

  Couplers and other non-assignable built-ins are intentionally excluded from
  setup-cell lookup so the UI does not auto-fill them as PDO drivers.

  Returns `{:ok, entry}` where `entry` is a map with `:module`, `:name`,
  `:identity`, `:vendor_id`, `:product_code`, `:revision`, `:assignable?`, and
  `:simulator?`, or `:error` if no assignable driver is registered for the
  given identity.
  """
  @spec lookup(%{vendor_id: non_neg_integer(), product_code: non_neg_integer()}) ::
          {:ok, map()} | :error
  def lookup(%{vendor_id: _vid, product_code: _pc} = identity) do
    case Enum.find(all(), &identity_matches?(&1.identity, identity)) do
      nil -> :error
      entry -> {:ok, entry}
    end
  end

  defp entry(module) do
    identity = SlaveDriver.identity(module) || %{}
    simulator_adapter = DriverAdapter.resolve(module, nil)
    signal_model = signal_model(module)

    %{
      module: module,
      name: module_name(module),
      identity: identity,
      vendor_id: Map.get(identity, :vendor_id),
      product_code: Map.get(identity, :product_code),
      revision: Map.get(identity, :revision, :any),
      assignable?: signal_model != [],
      simulator?: not is_nil(simulator_adapter)
    }
  end

  defp identity_matches?(
         %{vendor_id: vendor_id, product_code: product_code, revision: expected_revision},
         %{vendor_id: vendor_id, product_code: product_code} = identity
       ) do
    actual_revision = Map.get(identity, :revision, :any)
    expected_revision == :any or actual_revision == :any or actual_revision == expected_revision
  end

  defp identity_matches?(_registered, _identity), do: false

  defp module_name(module) do
    module
    |> Module.split()
    |> List.last()
  end

  defp signal_model(module) do
    SlaveDriver.signal_model(module, %{})
  rescue
    _ -> []
  end
end
