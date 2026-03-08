defmodule KinoEtherCAT.SetupCell do
  use Kino.JS, assets_path: "lib/assets/setup_cell/build"
  use Kino.JS.Live
  use Kino.SmartCell, name: "EtherCAT Setup"

  alias KinoEtherCAT.SetupSource

  @impl true
  def init(attrs, ctx) do
    slaves = attrs["slaves"] || []
    status = if slaves == [], do: :idle, else: :discovered
    Process.send_after(self(), :poll_phase, 500)

    {:ok,
     assign(ctx,
       interface: attrs["interface"] || "eth0",
       backup_interface: attrs["backup_interface"] || "",
       status: status,
       error: nil,
       slaves: slaves,
       domain_id: attrs["domain_id"] || "main",
       cycle_time_us: attrs["cycle_time_us"] || 1_000,
       activation_mode: attrs["activation_mode"] || "op",
       dc_enabled?: Map.get(attrs, "dc_enabled?", true),
       await_lock?: Map.get(attrs, "await_lock?", false),
       lock_threshold_ns: attrs["lock_threshold_ns"] || 100,
       lock_timeout_ms: attrs["lock_timeout_ms"] || 5_000,
       master_phase: :idle
     )}
  end

  @impl true
  def handle_connect(ctx) do
    drivers =
      Enum.map(KinoEtherCAT.Driver.all(), fn %{module: mod, name: name} ->
        %{module: inspect(mod), name: name}
      end)

    {:ok,
     %{
       interface: ctx.assigns.interface,
       status: to_string(ctx.assigns.status),
       error: ctx.assigns.error,
       slaves: ctx.assigns.slaves,
       backup_interface: ctx.assigns.backup_interface,
       domain_id: ctx.assigns.domain_id,
       cycle_time_us: ctx.assigns.cycle_time_us,
       activation_mode: ctx.assigns.activation_mode,
       dc_enabled?: ctx.assigns.dc_enabled?,
       await_lock?: ctx.assigns.await_lock?,
       lock_threshold_ns: ctx.assigns.lock_threshold_ns,
       lock_timeout_ms: ctx.assigns.lock_timeout_ms,
       master_phase: to_string(ctx.assigns.master_phase),
       available_drivers: drivers
     }, ctx}
  end

  @impl true
  def handle_event("scan", _params, ctx) do
    server = self()
    interface = ctx.assigns.interface
    Task.start(fn -> run_scan(server, interface) end)
    broadcast_event(ctx, "status", %{status: "scanning"})
    {:noreply, assign(ctx, status: :scanning, error: nil)}
  end

  def handle_event("stop", _params, ctx) do
    _ = EtherCAT.stop()
    broadcast_event(ctx, "status", %{status: "idle"})
    {:noreply, assign(ctx, status: :idle, error: nil)}
  end

  def handle_event("update_interface", %{"interface" => iface}, ctx) do
    {:noreply, assign(ctx, interface: iface)}
  end

  def handle_event("update_slave", %{"index" => idx, "name" => name, "driver" => driver}, ctx) do
    slaves =
      List.update_at(
        ctx.assigns.slaves,
        idx,
        &Map.merge(&1, %{"name" => name, "driver" => driver})
      )

    {:noreply, assign(ctx, slaves: slaves)}
  end

  def handle_event("update_runtime", params, ctx) do
    {:noreply,
     assign(ctx,
       backup_interface: Map.get(params, "backup_interface", ctx.assigns.backup_interface),
       domain_id: Map.get(params, "domain_id", ctx.assigns.domain_id),
       cycle_time_us: Map.get(params, "cycle_time_us", ctx.assigns.cycle_time_us),
       activation_mode: Map.get(params, "activation_mode", ctx.assigns.activation_mode),
       dc_enabled?: Map.get(params, "dc_enabled?", ctx.assigns.dc_enabled?),
       await_lock?: Map.get(params, "await_lock?", ctx.assigns.await_lock?),
       lock_threshold_ns: Map.get(params, "lock_threshold_ns", ctx.assigns.lock_threshold_ns),
       lock_timeout_ms: Map.get(params, "lock_timeout_ms", ctx.assigns.lock_timeout_ms)
     )}
  end

  @impl true
  def handle_info({:scan_complete, {:ok, slaves}}, ctx) do
    broadcast_event(ctx, "scan_result", %{slaves: slaves})
    {:noreply, assign(ctx, status: :discovered, slaves: slaves, error: nil)}
  end

  def handle_info({:scan_complete, {:error, reason}}, ctx) do
    broadcast_event(ctx, "scan_error", %{error: reason})
    {:noreply, assign(ctx, status: :error, error: reason)}
  end

  def handle_info(:poll_phase, ctx) do
    Process.send_after(self(), :poll_phase, 2_000)
    phase = EtherCAT.phase()

    if phase != ctx.assigns.master_phase do
      broadcast_event(ctx, "master_phase", %{phase: to_string(phase)})
      {:noreply, assign(ctx, master_phase: phase)}
    else
      {:noreply, ctx}
    end
  end

  @impl true
  def to_attrs(ctx) do
    %{
      "interface" => ctx.assigns.interface,
      "backup_interface" => ctx.assigns.backup_interface,
      "slaves" => ctx.assigns.slaves,
      "domain_id" => ctx.assigns.domain_id,
      "cycle_time_us" => ctx.assigns.cycle_time_us,
      "activation_mode" => ctx.assigns.activation_mode,
      "dc_enabled?" => ctx.assigns.dc_enabled?,
      "await_lock?" => ctx.assigns.await_lock?,
      "lock_threshold_ns" => ctx.assigns.lock_threshold_ns,
      "lock_timeout_ms" => ctx.assigns.lock_timeout_ms
    }
  end

  @impl true
  def to_source(attrs) do
    SetupSource.render(attrs)
  end

  defp run_scan(server, interface) do
    result =
      with :ok <- ensure_master_running(interface),
           :ok <- EtherCAT.await_running(15_000) do
        {:ok, discovered_slaves()}
      else
        {:error, reason} -> {:error, inspect(reason)}
      end

    send(server, {:scan_complete, result})
  rescue
    e -> send(server, {:scan_complete, {:error, Exception.message(e)}})
  end

  defp ensure_master_running(interface) do
    case EtherCAT.start(interface: interface) do
      :ok -> :ok
      {:error, :already_started} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp discovered_slaves do
    EtherCAT.slaves()
    |> Enum.map(fn %{name: name, station: station} ->
      identity =
        case EtherCAT.slave_info(name) do
          {:ok, %{identity: id}} when not is_nil(id) -> id
          _ -> %{}
        end

      driver =
        case KinoEtherCAT.Driver.lookup(identity) do
          {:ok, %{module: mod}} -> inspect(mod)
          :error -> ""
        end

      discovered_name = to_string(name)

      %{
        "station" => station,
        "vendor_id" => Map.get(identity, :vendor_id, 0),
        "product_code" => Map.get(identity, :product_code, 0),
        "name" => discovered_name,
        "discovered_name" => discovered_name,
        "driver" => driver
      }
    end)
  end
end
