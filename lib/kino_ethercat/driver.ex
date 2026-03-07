defmodule KinoEtherCAT.Driver do
  @moduledoc """
  Registry of built-in EtherCAT slave drivers shipped with KinoEtherCAT.

  Use `all/0` to enumerate available drivers (e.g. for a UI dropdown) and
  `lookup/1` to resolve a slave identity map to its driver module.
  """

  @drivers [
    %{
      module: KinoEtherCAT.Driver.EL1809,
      name: "EL1809",
      vendor_id: 0x00000002,
      product_code: 0x07113052
    },
    %{
      module: KinoEtherCAT.Driver.EL2809,
      name: "EL2809",
      vendor_id: 0x00000002,
      product_code: 0x0AF93052
    },
    %{
      module: KinoEtherCAT.Driver.EL3202,
      name: "EL3202",
      vendor_id: 0x00000002,
      product_code: 0x0C823052
    }
  ]

  @doc "Returns all registered drivers."
  def all, do: @drivers

  @doc """
  Looks up a driver by slave identity.

  Matches on `vendor_id` and `product_code` only.

  Returns `{:ok, entry}` where `entry` is a map with `:module`, `:name`,
  `:vendor_id`, and `:product_code`, or `:error` if no driver is registered
  for the given identity.
  """
  @spec lookup(%{vendor_id: non_neg_integer(), product_code: non_neg_integer()}) ::
          {:ok, map()} | :error
  def lookup(%{vendor_id: vid, product_code: pc}) do
    case Enum.find(@drivers, &(&1.vendor_id == vid and &1.product_code == pc)) do
      nil -> :error
      entry -> {:ok, entry}
    end
  end
end
