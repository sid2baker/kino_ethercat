defmodule KinoEtherCAT.Application do
  use Application

  @impl true
  def start(_type, _args) do
    Kino.SmartCell.register(KinoEtherCAT.SmartCells.Setup)
    Kino.SmartCell.register(KinoEtherCAT.SmartCells.Visualizer)
    Kino.SmartCell.register(KinoEtherCAT.SmartCells.SDOExplorer)
    Kino.SmartCell.register(KinoEtherCAT.SmartCells.RegisterExplorer)
    Kino.SmartCell.register(KinoEtherCAT.SmartCells.SIIExplorer)
    Supervisor.start_link([], strategy: :one_for_one, name: KinoEtherCAT.Supervisor)
  end
end
