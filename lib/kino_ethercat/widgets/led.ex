defmodule KinoEtherCAT.Widgets.LED do
  use Kino.JS, assets_path: "lib/assets/led/build"
  use Kino.JS.Live

  def new(slave, signal, opts \\ []) do
    Kino.JS.Live.new(__MODULE__, {slave, signal, opts})
  end

  @impl true
  def init({slave, signal, opts}, ctx) do
    case EtherCAT.subscribe(slave, signal) do
      :ok ->
        label = Keyword.get(opts, :label, "#{signal}")
        color = Keyword.get(opts, :color, "green")
        value = initial_value(slave, signal)

        {:ok, assign(ctx, slave: slave, signal: signal, value: value, label: label, color: color)}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_connect(ctx) do
    payload = %{value: ctx.assigns.value, label: ctx.assigns.label, color: ctx.assigns.color}
    {:ok, payload, ctx}
  end

  @impl true
  def handle_info({:ethercat, :signal, _slave, _signal, value}, ctx) do
    value = normalize_value(value)
    broadcast_event(ctx, "value_updated", %{value: value})
    {:noreply, assign(ctx, value: value)}
  end

  defp initial_value(slave, signal) do
    case EtherCAT.read_input(slave, signal) do
      {:ok, value} -> normalize_value(value)
      {:error, _reason} -> 0
    end
  end

  defp normalize_value({value, updated_at_us}) when is_integer(updated_at_us), do: value
  defp normalize_value(value), do: value
end
