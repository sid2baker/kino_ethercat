defmodule KinoEtherCAT.Runtime.Render do
  @moduledoc false

  def to_livebook(resource) do
    overview = KinoEtherCAT.Runtime.Panel.new(resource)
    raw = Kino.Inspect.new(resource)
    kino = Kino.Layout.tabs(Overview: overview, Raw: raw)
    Kino.Render.to_livebook(kino)
  end
end

for module <- [EtherCAT.Master, EtherCAT.Slave, EtherCAT.Domain, EtherCAT.Bus] do
  defimpl Kino.Render, for: module do
    def to_livebook(resource), do: KinoEtherCAT.Runtime.Render.to_livebook(resource)
  end
end

if Code.ensure_loaded?(EtherCAT.DC.Status) and
     function_exported?(EtherCAT.DC.Status, :__struct__, 0) do
  defimpl Kino.Render, for: EtherCAT.DC.Status do
    def to_livebook(resource), do: KinoEtherCAT.Runtime.Render.to_livebook(resource)
  end
end

if function_exported?(EtherCAT.DC, :__struct__, 0) do
  defimpl Kino.Render, for: EtherCAT.DC do
    def to_livebook(resource), do: KinoEtherCAT.Runtime.Render.to_livebook(resource)
  end
end
