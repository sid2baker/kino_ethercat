defmodule KinoEtherCAT.Runtime.Live do
  @moduledoc false

  alias Kino.JS.Live.Context
  alias KinoEtherCAT.Runtime

  def init(resource, ctx) do
    payload = Runtime.payload(resource)
    {:ok, Context.assign(ctx, resource: resource, payload: payload)}
  end

  def handle_connect(ctx) do
    {:ok, ctx.assigns.payload, ctx}
  end

  def handle_event("action", %{"id" => id} = params, ctx) do
    case Runtime.perform(ctx.assigns.resource, id, params) do
      {:ok, resource, message} ->
        payload = Runtime.payload(resource, message)
        Context.broadcast_event(ctx, "snapshot", payload)
        {:noreply, Context.assign(ctx, resource: resource, payload: payload)}

      {:error, resource, message} ->
        payload = Runtime.payload(resource, message)
        Context.broadcast_event(ctx, "snapshot", payload)
        {:noreply, Context.assign(ctx, resource: resource, payload: payload)}
    end
  end
end
