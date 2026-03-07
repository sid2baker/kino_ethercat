defmodule KinoEtherCAT.Application do
  use Application

  @impl true
  def start(_type, _args) do
    Kino.SmartCell.register(KinoEtherCAT.StartCell)
    Supervisor.start_link([], strategy: :one_for_one, name: KinoEtherCAT.Supervisor)
  end
end
