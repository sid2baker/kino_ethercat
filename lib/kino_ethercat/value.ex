defmodule KinoEtherCAT.Value do
  use Kino.JS, assets_path: "lib/assets/value/build"
  use Kino.JS.Live

  def new(slave, signal, opts \\ []) do
    Kino.JS.Live.new(__MODULE__, {slave, signal, opts})
  end

  @impl true
  def init({slave, signal, opts}, ctx) do
    case EtherCAT.subscribe(slave, signal) do
      :ok ->
        label = Keyword.get(opts, :label, "#{signal}")
        {:ok, assign(ctx, label: label, value: nil)}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_connect(ctx) do
    {:ok, %{label: ctx.assigns.label, value: ctx.assigns.value}, ctx}
  end

  @impl true
  def handle_info({:ethercat, :signal, _slave, _signal, value}, ctx) do
    broadcast_event(ctx, "value_updated", %{value: inspect(value)})
    {:noreply, assign(ctx, value: value)}
  end
end
