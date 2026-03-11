defmodule KinoEtherCAT.Introduction do
  @moduledoc """
  Simulator-first teaching surfaces for learning EtherCAT concepts interactively.
  """

  alias KinoEtherCAT.Introduction.Panel

  @spec panel() :: Kino.JS.Live.t()
  def panel, do: Panel.new()
end
