defimpl Kino.Render, for: EtherCAT.Master do
  def to_livebook(master) do
    overview = KinoEtherCAT.Runtime.Panel.new(master)
    raw = Kino.Inspect.new(master)
    Kino.Render.to_livebook(Kino.Layout.tabs(Overview: overview, Raw: raw))
  end
end

defimpl Kino.Render, for: EtherCAT.Slave do
  def to_livebook(slave) do
    overview = KinoEtherCAT.Runtime.Panel.new(slave)
    raw = Kino.Inspect.new(slave)
    Kino.Render.to_livebook(Kino.Layout.tabs(Overview: overview, Raw: raw))
  end
end

defimpl Kino.Render, for: EtherCAT.Domain do
  def to_livebook(domain) do
    overview = KinoEtherCAT.Runtime.Panel.new(domain)
    raw = Kino.Inspect.new(domain)
    Kino.Render.to_livebook(Kino.Layout.tabs(Overview: overview, Raw: raw))
  end
end

defimpl Kino.Render, for: EtherCAT.Bus do
  def to_livebook(bus) do
    overview = KinoEtherCAT.Runtime.Panel.new(bus)
    raw = Kino.Inspect.new(bus)
    Kino.Render.to_livebook(Kino.Layout.tabs(Overview: overview, Raw: raw))
  end
end

defimpl Kino.Render, for: EtherCAT.DC.Status do
  def to_livebook(status) do
    overview = KinoEtherCAT.Runtime.Panel.new(status)
    raw = Kino.Inspect.new(status)
    Kino.Render.to_livebook(Kino.Layout.tabs(Overview: overview, Raw: raw))
  end
end
