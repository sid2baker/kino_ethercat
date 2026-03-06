defmodule KinoEtherCAT.LED do
  use Kino.JS, assets_path: "lib/assets/led/build"
  use Kino.JS.Live

  def new(slave, signal, opts \\ []) do
    Kino.JS.Live.new(__MODULE__, {slave, signal, opts})
  end

  @impl true
  def init({slave, signal, opts}, ctx) do
    EtherCAT.subscribe(slave, signal)

    label = Keyword.get(opts, :label, "#{slave}.#{signal}")
    color = Keyword.get(opts, :color, "green")

    {:ok, assign(ctx, slave: slave, signal: signal, value: 0, label: label, color: color)}
  end

  @impl true
  def handle_connect(ctx) do
    payload = %{value: ctx.assigns.value, label: ctx.assigns.label, color: ctx.assigns.color}
    {:ok, payload, ctx}
  end

  @impl true
  def handle_info({:ethercat, :signal, _slave, _signal, value}, ctx) do
    broadcast_event(ctx, "value_updated", %{value: value})
    {:noreply, assign(ctx, value: value)}
  end
end
