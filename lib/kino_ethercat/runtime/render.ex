defmodule KinoEtherCAT.Runtime.Render do
  @moduledoc false

  def to_livebook(kino), do: Kino.Render.to_livebook(kino)
end

defimpl Kino.Render, for: EtherCAT.Master do
  def to_livebook(resource) do
    kino = KinoEtherCAT.Runtime.Master.new(resource)
    KinoEtherCAT.Runtime.Render.to_livebook(kino)
  end
end

defimpl Kino.Render, for: EtherCAT.Slave do
  def to_livebook(resource) do
    kino = KinoEtherCAT.Runtime.Slave.new(resource)
    KinoEtherCAT.Runtime.Render.to_livebook(kino)
  end
end

defimpl Kino.Render, for: EtherCAT.Domain do
  def to_livebook(resource) do
    kino = KinoEtherCAT.Runtime.Domain.new(resource)
    KinoEtherCAT.Runtime.Render.to_livebook(kino)
  end
end

defimpl Kino.Render, for: EtherCAT.Bus do
  def to_livebook(resource) do
    kino = KinoEtherCAT.Runtime.Bus.new(resource)
    KinoEtherCAT.Runtime.Render.to_livebook(kino)
  end
end

if function_exported?(EtherCAT.DC, :__struct__, 0) do
  defimpl Kino.Render, for: EtherCAT.DC do
    def to_livebook(resource) do
      kino = KinoEtherCAT.Runtime.DC.new(resource)
      KinoEtherCAT.Runtime.Render.to_livebook(kino)
    end
  end
end

if Code.ensure_loaded?(EtherCAT.DC.Status) and
     function_exported?(EtherCAT.DC.Status, :__struct__, 0) do
  defimpl Kino.Render, for: EtherCAT.DC.Status do
    def to_livebook(resource) do
      kino = KinoEtherCAT.Runtime.DC.new(resource)
      KinoEtherCAT.Runtime.Render.to_livebook(kino)
    end
  end
end
