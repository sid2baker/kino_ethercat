defmodule KinoEtherCAT.Diagnostics.Panel do
  @moduledoc """
  Live diagnostic dashboard for an EtherCAT master.

  Combines low-rate runtime polling with EtherCAT telemetry so the dashboard
  can show current master state, rolling latency and cycle trends, and a fault
  timeline in a single widget.

  Use `KinoEtherCAT.Diagnostics.panel/0` to create one.
  """

  use Kino.JS, assets_path: "lib/assets/diagnostics/build"
  use Kino.JS.Live

  alias KinoEtherCAT.Diagnostics.State

  @poll_ms 1_000
  @flush_ms 250
  @events EtherCAT.Telemetry.events()

  @doc false
  def new do
    Kino.JS.Live.new(__MODULE__, nil)
  end

  @impl true
  def init(_arg, ctx) do
    handler_id = "kino-ethercat-diagnostics-#{System.unique_integer([:positive, :monotonic])}"
    :ok = :telemetry.attach_many(handler_id, @events, &__MODULE__.handle_telemetry/4, self())

    schedule_poll()

    diagnostics_state =
      State.new()
      |> State.apply_poll_snapshot(fetch_snapshot())

    {:ok,
     assign(ctx,
       handler_id: handler_id,
       diagnostics_state: diagnostics_state,
       payload: State.payload(diagnostics_state),
       flush_scheduled?: false
     )}
  end

  @impl true
  def handle_connect(ctx) do
    {:ok, ctx.assigns.payload, ctx}
  end

  @impl true
  def handle_info(:poll, ctx) do
    schedule_poll()

    diagnostics_state =
      ctx.assigns.diagnostics_state
      |> State.apply_poll_snapshot(fetch_snapshot())

    ctx =
      ctx
      |> assign(diagnostics_state: diagnostics_state)
      |> schedule_flush()

    {:noreply, ctx}
  end

  def handle_info({:telemetry_event, event, measurements, metadata}, ctx) do
    diagnostics_state =
      State.apply_telemetry(
        ctx.assigns.diagnostics_state,
        event,
        measurements,
        metadata
      )

    ctx =
      ctx
      |> assign(diagnostics_state: diagnostics_state)
      |> schedule_flush()

    {:noreply, ctx}
  end

  def handle_info(:flush, ctx) do
    payload = State.payload(ctx.assigns.diagnostics_state)
    broadcast_event(ctx, "snapshot", payload)

    {:noreply, assign(ctx, payload: payload, flush_scheduled?: false)}
  end

  @impl true
  def terminate(_reason, ctx) do
    :telemetry.detach(ctx.assigns.handler_id)
    :ok
  end

  @doc false
  def handle_telemetry(event, measurements, metadata, pid) do
    send(pid, {:telemetry_event, event, measurements, metadata})
  end

  defp schedule_poll, do: Process.send_after(self(), :poll, @poll_ms)

  defp schedule_flush(%{assigns: %{flush_scheduled?: true}} = ctx), do: ctx

  defp schedule_flush(ctx) do
    Process.send_after(self(), :flush, @flush_ms)
    assign(ctx, flush_scheduled?: true)
  end

  defp fetch_snapshot do
    %{
      state: fetch_state(),
      last_failure: fetch_last_failure(),
      slaves: fetch_slaves(),
      domains: fetch_domains(),
      dc: fetch_dc()
    }
  end

  defp fetch_slaves do
    safe(
      fn ->
        case EtherCAT.slaves() do
          {:ok, slaves} when is_list(slaves) ->
            Enum.map(slaves, fn %{name: name, station: station, fault: fault} ->
              {al_state, config_error} =
                case EtherCAT.slave_info(name) do
                  {:ok, info} -> {info.al_state, info.configuration_error}
                  _ -> {:unknown, nil}
                end

              al_error =
                case EtherCAT.Slave.error(name) do
                  code when is_integer(code) -> code
                  _ -> nil
                end

              %{
                name: to_string(name),
                station: station,
                al_state: to_string(al_state),
                al_error: al_error,
                fault: nil_or_string(fault),
                configuration_error: nil_or_string(config_error)
              }
            end)

          _ ->
            []
        end
      end,
      []
    )
  end

  defp fetch_domains do
    safe(
      fn ->
        case EtherCAT.domains() do
          {:ok, domains} when is_list(domains) ->
            Enum.map(domains, fn {id, cycle_time_us, _pid} ->
              info =
                case EtherCAT.domain_info(id) do
                  {:ok, i} -> i
                  _ -> %{}
                end

              %{
                id: to_string(id),
                cycle_time_us: cycle_time_us,
                state: to_string(Map.get(info, :state, :unknown)),
                cycle_health: format_cycle_health(Map.get(info, :cycle_health, :healthy)),
                cycle_count: Map.get(info, :cycle_count, 0),
                miss_count: Map.get(info, :miss_count, 0),
                total_miss_count: Map.get(info, :total_miss_count, 0),
                expected_wkc: Map.get(info, :expected_wkc, 0),
                logical_base: Map.get(info, :logical_base),
                image_size: Map.get(info, :image_size),
                last_invalid_cycle_at_us: Map.get(info, :last_invalid_cycle_at_us),
                last_invalid_reason: format_invalid_reason(Map.get(info, :last_invalid_reason))
              }
            end)

          _ ->
            []
        end
      end,
      []
    )
  end

  defp fetch_dc do
    safe(
      fn ->
        case EtherCAT.dc_status() do
          {:ok, %{configured?: configured, active?: active} = s} ->
            %{
              configured: configured,
              active: active,
              lock_state: to_string(s.lock_state),
              reference_clock: nil_or_string(s.reference_clock),
              reference_station: Map.get(s, :reference_station),
              max_sync_diff_ns: s.max_sync_diff_ns,
              cycle_ns: s.cycle_ns,
              monitor_failures: s.monitor_failures,
              await_lock: Map.get(s, :await_lock?),
              lock_policy: nil_or_string(Map.get(s, :lock_policy))
            }

          _ ->
            nil
        end
      end,
      nil
    )
  end

  defp fetch_state do
    case safe(fn -> EtherCAT.state() end, :idle) do
      {:ok, state} when is_atom(state) -> to_string(state)
      _ -> "idle"
    end
  end

  defp fetch_last_failure do
    case safe(fn -> EtherCAT.last_failure() end, nil) do
      {:ok, failure} when is_map(failure) -> format_failure(failure)
      _ -> nil
    end
  end

  defp safe(fun, default) do
    fun.()
  rescue
    _ -> default
  catch
    :exit, _ -> default
  end

  defp nil_or_string(nil), do: nil
  defp nil_or_string(v), do: to_string(v)

  defp format_cycle_health(:healthy), do: %{state: "healthy", detail: nil}

  defp format_cycle_health({:invalid, reason}) do
    %{state: "invalid", detail: format_invalid_reason(reason)}
  end

  defp format_cycle_health(other), do: %{state: to_string(other), detail: nil}

  defp format_invalid_reason(nil), do: nil
  defp format_invalid_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_invalid_reason(reason) when is_binary(reason), do: reason
  defp format_invalid_reason(reason), do: inspect(reason, pretty: false, limit: 20)

  defp format_failure(nil), do: nil
  defp format_failure(map), do: inspect(map, pretty: false, limit: 20)
end
