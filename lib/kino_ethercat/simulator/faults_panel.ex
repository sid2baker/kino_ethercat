defmodule KinoEtherCAT.Simulator.FaultsPanel do
  @moduledoc false

  use Kino.JS, assets_path: "lib/assets/simulator_faults_panel/build"
  use Kino.JS.Live

  alias Kino.JS.Live.Context
  alias KinoEtherCAT.Simulator.FaultsView

  @refresh_interval_ms 1_000

  @spec new() :: Kino.JS.Live.t()
  def new, do: Kino.JS.Live.new(__MODULE__, nil)

  @impl true
  def init(_arg, ctx) do
    payload = FaultsView.payload()
    schedule_refresh()
    {:ok, Context.assign(ctx, payload: payload, message: payload.message)}
  end

  @impl true
  def handle_connect(ctx) do
    {:ok, ctx.assigns.payload, ctx}
  end

  @impl true
  def handle_event("action", %{"id" => id} = params, ctx) do
    message = FaultsView.perform(id, Map.delete(params, "id"))
    ctx = Context.assign(ctx, message: message)
    {:noreply, broadcast_snapshot(ctx)}
  end

  @impl true
  def handle_info(:refresh_snapshot, ctx) do
    schedule_refresh()
    {:noreply, broadcast_snapshot(ctx)}
  end

  def handle_info(_message, ctx), do: {:noreply, ctx}

  defp schedule_refresh do
    Process.send_after(self(), :refresh_snapshot, @refresh_interval_ms)
  end

  defp broadcast_snapshot(ctx) do
    payload = FaultsView.payload(ctx.assigns.message)

    if payload != ctx.assigns.payload do
      Context.broadcast_event(ctx, "snapshot", payload)
    end

    Context.assign(ctx, payload: payload)
  end
end
