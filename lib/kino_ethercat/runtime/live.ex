defmodule KinoEtherCAT.Runtime.Live do
  @moduledoc false

  alias Kino.JS.Live.Context
  alias KinoEtherCAT.Runtime

  def init(resource, ctx) do
    Runtime.subscribe_logs(self(), resource)
    payload = Runtime.payload(resource)

    {:ok,
     Context.assign(ctx,
       resource: resource,
       payload: payload,
       log_scope: Runtime.log_scope(resource),
       log_refresh_pending?: false
     )}
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

  def handle_info({:kino_ethercat, :logs_updated, scope}, ctx) do
    if ctx.assigns.log_scope == scope do
      maybe_schedule_log_refresh(ctx)
    else
      {:noreply, ctx}
    end
  end

  def handle_info(:refresh_logs, ctx) do
    payload = Runtime.payload(ctx.assigns.resource, ctx.assigns.payload.message)
    Context.broadcast_event(ctx, "snapshot", payload)

    {:noreply, Context.assign(ctx, payload: payload, log_refresh_pending?: false)}
  end

  def handle_info(_message, ctx), do: {:noreply, ctx}

  defp maybe_schedule_log_refresh(ctx) do
    if ctx.assigns.log_refresh_pending? do
      {:noreply, ctx}
    else
      Process.send_after(self(), :refresh_logs, 50)
      {:noreply, Context.assign(ctx, log_refresh_pending?: true)}
    end
  end
end
