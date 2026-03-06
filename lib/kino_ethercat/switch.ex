defmodule KinoEtherCAT.Switch do
  use Kino.JS, assets_path: "lib/assets/switch/build"
  use Kino.JS.Live

  def new(slave, signal, opts \\ []) do
    Kino.JS.Live.new(__MODULE__, {slave, signal, opts})
  end

  @impl true
  def init({slave, signal, opts}, ctx) do
    label = Keyword.get(opts, :label, "#{slave}.#{signal}")
    initial = Keyword.get(opts, :initial, 0)

    {:ok, assign(ctx, slave: slave, signal: signal, value: initial, label: label)}
  end

  @impl true
  def handle_connect(ctx) do
    payload = %{value: ctx.assigns.value, label: ctx.assigns.label}
    {:ok, payload, ctx}
  end

  @impl true
  def handle_event("toggle", _params, ctx) do
    new_value = if ctx.assigns.value == 0, do: 1, else: 0
    EtherCAT.write_output(ctx.assigns.slave, ctx.assigns.signal, new_value)
    broadcast_event(ctx, "value_updated", %{value: new_value})
    {:noreply, assign(ctx, value: new_value)}
  end
end
