defmodule KinoEtherCAT.Runtime.Panel do
  @moduledoc false

  use Kino.JS, assets_path: "lib/assets/runtime_panel/build"
  use Kino.JS.Live

  alias KinoEtherCAT.Runtime

  @spec new(struct()) :: Kino.JS.Live.t()
  def new(resource) do
    Kino.JS.Live.new(__MODULE__, resource)
  end

  @impl true
  def init(resource, ctx) do
    payload = Runtime.payload(resource)
    {:ok, assign(ctx, resource: resource, payload: payload)}
  end

  @impl true
  def handle_connect(ctx) do
    {:ok, ctx.assigns.payload, ctx}
  end

  @impl true
  def handle_event("action", %{"id" => id} = params, ctx) do
    case Runtime.perform(ctx.assigns.resource, id, params) do
      {:ok, resource, message} ->
        payload = Runtime.payload(resource, message)
        broadcast_event(ctx, "snapshot", payload)
        {:noreply, assign(ctx, resource: resource, payload: payload)}

      {:error, resource, message} ->
        payload = Runtime.payload(resource, message)
        broadcast_event(ctx, "snapshot", payload)
        {:noreply, assign(ctx, resource: resource, payload: payload)}
    end
  end
end
