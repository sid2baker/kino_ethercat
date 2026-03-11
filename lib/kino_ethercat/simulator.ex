defmodule KinoEtherCAT.Simulator do
  @moduledoc """
  Namespaced entrypoints for EtherCAT simulator renders.
  """

  alias KinoEtherCAT.Simulator.{FaultsPanel, Panel}

  @spec panel() :: Kino.JS.Live.t()
  def panel, do: Panel.new()

  @spec faults_panel() :: Kino.JS.Live.t()
  def faults_panel, do: FaultsPanel.new()
end
