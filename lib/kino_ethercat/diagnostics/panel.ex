defmodule KinoEtherCAT.Diagnostics do
  @moduledoc """
  Live diagnostic dashboard for an EtherCAT master.

  Polls `EtherCAT.phase/0`, slave states, domain cycle stats, and DC lock
  status every 500 ms and renders a live dashboard widget.

  Use `KinoEtherCAT.diagnostics/0` to create one.
  """

  use Kino.JS, assets_path: "lib/assets/diagnostics/build"
  use Kino.JS.Live

  @poll_ms 500

  @doc false
  def new do
    Kino.JS.Live.new(__MODULE__, nil)
  end

  @impl true
  def init(_arg, ctx) do
    schedule_poll()
    {:ok, assign(ctx, snapshot: fetch_snapshot())}
  end

  @impl true
  def handle_connect(ctx) do
    {:ok, ctx.assigns.snapshot, ctx}
  end

  @impl true
  def handle_info(:poll, ctx) do
    schedule_poll()
    snapshot = fetch_snapshot()
    broadcast_event(ctx, "snapshot", snapshot)
    {:noreply, assign(ctx, snapshot: snapshot)}
  end

  defp schedule_poll, do: Process.send_after(self(), :poll, @poll_ms)

  defp fetch_snapshot do
    %{
      phase: to_string(safe(fn -> EtherCAT.phase() end, :idle)),
      last_failure: format_failure(safe(fn -> EtherCAT.last_failure() end, nil)),
      slaves: fetch_slaves(),
      domains: fetch_domains(),
      dc: fetch_dc()
    }
  end

  defp fetch_slaves do
    safe(
      fn ->
        EtherCAT.slaves()
        |> Enum.map(fn %{name: name, station: station} ->
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
            configuration_error: nil_or_string(config_error)
          }
        end)
      end,
      []
    )
  end

  defp fetch_domains do
    safe(
      fn ->
        EtherCAT.domains()
        |> Enum.map(fn {id, cycle_time_us, _pid} ->
          info =
            case EtherCAT.domain_info(id) do
              {:ok, i} -> i
              _ -> %{}
            end

          %{
            id: to_string(id),
            cycle_time_us: cycle_time_us,
            state: to_string(Map.get(info, :state, :unknown)),
            cycle_count: Map.get(info, :cycle_count, 0),
            miss_count: Map.get(info, :miss_count, 0),
            total_miss_count: Map.get(info, :total_miss_count, 0),
            expected_wkc: Map.get(info, :expected_wkc, 0)
          }
        end)
      end,
      []
    )
  end

  defp fetch_dc do
    safe(
      fn ->
        s = EtherCAT.dc_status()

        %{
          configured: s.configured?,
          active: s.active?,
          lock_state: to_string(s.lock_state),
          reference_clock: nil_or_string(s.reference_clock),
          max_sync_diff_ns: s.max_sync_diff_ns,
          cycle_ns: s.cycle_ns,
          monitor_failures: s.monitor_failures
        }
      end,
      nil
    )
  end

  defp safe(fun, default) do
    fun.()
  rescue
    _ -> default
  end

  defp nil_or_string(nil), do: nil
  defp nil_or_string(v), do: to_string(v)

  defp format_failure(nil), do: nil
  defp format_failure(map), do: inspect(map, pretty: false, limit: 20)
end
