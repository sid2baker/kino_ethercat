defmodule KinoEtherCAT.Runtime.Live do
  @moduledoc false

  alias Kino.JS.Live.Context
  alias KinoEtherCAT.Runtime

  @refresh_interval_ms 1_000

  def init(resource, ctx) do
    Runtime.subscribe_logs(self(), resource)
    payload = Runtime.payload(resource)
    schedule_refresh()

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
        {:noreply, broadcast_snapshot(ctx, resource, message)}

      {:error, resource, message} ->
        {:noreply, broadcast_snapshot(ctx, resource, message)}
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
    ctx =
      ctx
      |> broadcast_snapshot(ctx.assigns.resource, ctx.assigns.payload.message)
      |> Context.assign(log_refresh_pending?: false)

    {:noreply, ctx}
  end

  def handle_info(:refresh_snapshot, ctx) do
    resource = Runtime.refresh(ctx.assigns.resource)
    ctx = broadcast_snapshot(ctx, resource, ctx.assigns.payload.message)
    schedule_refresh()
    {:noreply, ctx}
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

  defp schedule_refresh do
    Process.send_after(self(), :refresh_snapshot, @refresh_interval_ms)
  end

  defp broadcast_snapshot(ctx, resource, message) do
    payload = Runtime.payload(resource, message)

    if payload != ctx.assigns.payload do
      Context.broadcast_event(ctx, "snapshot", payload)
    end

    Context.assign(ctx, resource: resource, payload: payload)
  end
end
