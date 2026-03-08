defmodule KinoEtherCAT.Diagnostics do
  @moduledoc """
  Namespaced entrypoints for telemetry-driven EtherCAT diagnostics.
  """

  alias KinoEtherCAT.Diagnostics.Panel

  @spec panel() :: Kino.JS.Live.t()
  def panel, do: Panel.new()
end
