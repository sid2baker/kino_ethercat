defmodule KinoEtherCAT.Widgets.Value do
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
        sample = input_sample(slave, signal)

        {:ok,
         assign(ctx,
           slave: slave,
           signal: signal,
           label: label,
           value: sample.value,
           updated_at_us: sample.updated_at_us
         )}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_connect(ctx) do
    {:ok,
     %{
       label: ctx.assigns.label,
       value: ctx.assigns.value,
       updated_at_us: ctx.assigns.updated_at_us
     }, ctx}
  end

  @impl true
  def handle_info({:ethercat, :signal, _slave, _signal, value}, ctx) do
    sample = input_sample(ctx.assigns.slave, ctx.assigns.signal, value, ctx.assigns.updated_at_us)
    broadcast_event(ctx, "value_updated", sample)
    {:noreply, assign(ctx, value: sample.value, updated_at_us: sample.updated_at_us)}
  end

  defp input_sample(slave, signal, fallback_value \\ nil, fallback_updated_at_us \\ nil) do
    case EtherCAT.read_input(slave, signal) do
      {:ok, {value, updated_at_us}} when is_integer(updated_at_us) ->
        %{value: inspect(value), updated_at_us: updated_at_us}

      {:ok, value} ->
        %{value: inspect(value), updated_at_us: fallback_updated_at_us}

      {:error, _reason} when is_nil(fallback_value) ->
        %{value: nil, updated_at_us: fallback_updated_at_us}

      {:error, _reason} ->
        %{value: inspect(fallback_value), updated_at_us: fallback_updated_at_us}
    end
  end
end
