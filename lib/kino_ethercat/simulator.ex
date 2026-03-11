defmodule KinoEtherCAT.Simulator do
  @moduledoc """
  Namespaced entrypoint for the EtherCAT simulator control panel.
  """

  alias KinoEtherCAT.Simulator.Panel

  @spec panel() :: Kino.JS.Live.t()
  def panel, do: Panel.new()
end
