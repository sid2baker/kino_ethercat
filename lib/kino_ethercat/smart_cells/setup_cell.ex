defmodule KinoEtherCAT.SmartCells.Setup do
  use Kino.JS, assets_path: "lib/assets/setup_cell/build"
  use Kino.JS.Live
  use Kino.SmartCell, name: "EtherCAT Setup"

  alias KinoEtherCAT.SmartCells.{BusSetup, SetupSource, SetupTransport, SimulatorConfig}

  @scan_await_timeout_ms 30_000
  @scan_frame_timeout_ms 25
  @scan_retry_delay_ms 300
  @scan_stable_ms 250
  @scan_poll_ms 100

  @impl true
  def init(attrs, ctx) do
    config = normalize_attrs(attrs)
    status = if config.slaves == [], do: :idle, else: :discovered

    if should_auto_scan?(attrs, config), do: Process.send_after(self(), :auto_scan, 0)
    Process.send_after(self(), :poll_state, 500)

    {:ok,
     assign(ctx,
       status: status,
       scan_task: nil,
       error: nil,
       master_state: BusSetup.runtime_state(),
       master_pid: Process.whereis(EtherCAT.Master),
       available_interfaces: BusSetup.available_interfaces(),
       transport_mode: config.transport_mode,
       transport: config.transport,
       interface: config.interface,
       backup_interface: config.backup_interface,
       host: config.host,
       port: config.port,
       slaves: config.slaves,
       domains: config.domains,
       dc_enabled: config.dc_enabled,
       dc_cycle_ns: config.dc_cycle_ns,
       await_lock: config.await_lock,
       lock_threshold_ns: config.lock_threshold_ns,
       lock_timeout_ms: config.lock_timeout_ms,
       warmup_cycles: config.warmup_cycles
     )}
  end

  @impl true
  def handle_connect(ctx) do
    {:ok, payload(ctx.assigns), ctx}
  end

  @impl true
  def handle_event("scan", _params, ctx) do
    {:noreply, begin_scan(ctx)}
  end

  def handle_event("stop", _params, ctx) do
    cancel_scan(ctx.assigns.scan_task)
    _ = EtherCAT.stop()

    ctx =
      assign(ctx,
        status: :idle,
        scan_task: nil,
        error: nil,
        master_state: :idle,
        master_pid: nil
      )

    broadcast_event(ctx, "snapshot", payload(ctx.assigns))
    {:noreply, ctx}
  end

  def handle_event("update", params, ctx) do
    config = normalize_attrs(params)

    ctx =
      assign(ctx,
        available_interfaces: BusSetup.available_interfaces(),
        transport_mode: config.transport_mode,
        transport: config.transport,
        interface: config.interface,
        backup_interface: config.backup_interface,
        host: config.host,
        port: config.port,
        slaves: config.slaves,
        domains: config.domains,
        dc_enabled: config.dc_enabled,
        dc_cycle_ns: config.dc_cycle_ns,
        await_lock: config.await_lock,
        lock_threshold_ns: config.lock_threshold_ns,
        lock_timeout_ms: config.lock_timeout_ms,
        warmup_cycles: config.warmup_cycles
      )

    broadcast_event(ctx, "snapshot", payload(ctx.assigns))
    {:noreply, ctx}
  end

  @impl true
  def handle_info({:scan_complete, _result}, %{assigns: %{scan_task: nil}} = ctx) do
    # Scan was cancelled (e.g. user clicked stop); ignore stale result.
    {:noreply, ctx}
  end

  def handle_info({:scan_complete, {:ok, slaves}}, ctx) do
    ctx =
      assign(ctx,
        status: :discovered,
        scan_task: nil,
        slaves: slaves,
        error: nil,
        master_state: BusSetup.runtime_state(),
        master_pid: Process.whereis(EtherCAT.Master),
        available_interfaces: BusSetup.available_interfaces()
      )

    broadcast_event(ctx, "snapshot", payload(ctx.assigns))
    {:noreply, ctx}
  end

  def handle_info({:scan_complete, {:error, reason}}, ctx) do
    ctx = assign(ctx, status: :error, scan_task: nil, error: reason)
    broadcast_event(ctx, "snapshot", payload(ctx.assigns))
    {:noreply, ctx}
  end

  def handle_info(:auto_scan, ctx) do
    if ctx.assigns.status == :idle and ctx.assigns.slaves == [] and simulator_running?() do
      {:noreply, begin_scan(ctx)}
    else
      {:noreply, ctx}
    end
  end

  def handle_info(:poll_state, ctx) do
    Process.send_after(self(), :poll_state, 2_000)

    state = BusSetup.runtime_state()
    pid = Process.whereis(EtherCAT.Master)
    interfaces = BusSetup.available_interfaces()
    transport = ctx.assigns |> BusSetup.transport_assigns() |> SetupTransport.refresh_auto()

    if state != ctx.assigns.master_state or
         pid != ctx.assigns.master_pid or
         interfaces != ctx.assigns.available_interfaces or
         BusSetup.transport_changed?(ctx.assigns, transport) do
      ctx =
        ctx
        |> assign(master_state: state, master_pid: pid, available_interfaces: interfaces)
        |> assign_transport(transport)

      broadcast_event(ctx, "snapshot", payload(ctx.assigns))
      {:noreply, ctx}
    else
      {:noreply, ctx}
    end
  end

  @impl true
  def to_attrs(ctx) do
    %{
      "transport_mode" => Atom.to_string(ctx.assigns.transport_mode),
      "transport" => Atom.to_string(ctx.assigns.transport),
      "interface" => ctx.assigns.interface,
      "backup_interface" => ctx.assigns.backup_interface,
      "host" => ctx.assigns.host,
      "port" => ctx.assigns.port,
      "slaves" => ctx.assigns.slaves,
      "domains" => ctx.assigns.domains,
      "dc_enabled" => ctx.assigns.dc_enabled,
      "dc_cycle_ns" => ctx.assigns.dc_cycle_ns,
      "await_lock" => ctx.assigns.await_lock,
      "lock_threshold_ns" => ctx.assigns.lock_threshold_ns,
      "lock_timeout_ms" => ctx.assigns.lock_timeout_ms,
      "warmup_cycles" => ctx.assigns.warmup_cycles
    }
  end

  @impl true
  def to_source(attrs) do
    SetupSource.render(attrs)
  end

  @doc false
  def should_auto_scan?(attrs, %{slaves: slaves}, simulator_running? \\ &simulator_running?/0)
      when is_map(attrs) and is_list(slaves) and is_function(simulator_running?, 0) do
    map_size(attrs) == 0 and slaves == [] and simulator_running?.()
  end

  defp begin_scan(ctx) do
    cancel_scan(ctx.assigns.scan_task)

    server = self()
    transport = ctx.assigns |> BusSetup.transport_assigns() |> SetupTransport.refresh_auto()
    ctx = assign_transport(ctx, transport)

    {:ok, pid} =
      Task.start(fn ->
        run_scan(server, transport, ctx.assigns.slaves, ctx.assigns.domains)
      end)

    ctx = assign(ctx, status: :scanning, scan_task: pid, error: nil)
    broadcast_event(ctx, "snapshot", payload(ctx.assigns))
    ctx
  end

  defp cancel_scan(pid) when is_pid(pid), do: Process.exit(pid, :kill)
  defp cancel_scan(nil), do: :ok

  defp run_scan(server, transport, existing_slaves, domains) do
    result =
      case scan_discovered_slaves(transport, existing_slaves, domains) do
        {:ok, _slaves} = ok -> ok
        {:error, reason} when is_binary(reason) -> {:error, reason}
        {:error, reason} -> {:error, inspect(reason)}
      end

    send(server, {:scan_complete, result})
  rescue
    e -> send(server, {:scan_complete, {:error, Exception.message(e)}})
  end

  defp scan_discovered_slaves(transport, existing_slaves, domains) do
    with {:ok, slaves} <- scan_discovered_slaves_once(transport, existing_slaves, domains) do
      {:ok, slaves}
    else
      {:error, reason} = error ->
        if retryable_scan_reason?(reason) do
          Process.sleep(@scan_retry_delay_ms)

          transport
          |> SetupTransport.refresh_auto()
          |> scan_discovered_slaves_once(existing_slaves, domains)
        else
          error
        end
    end
  end

  defp scan_discovered_slaves_once(transport, existing_slaves, domains) do
    with {:ok, start_opts} <- SetupTransport.runtime_start_opts(transport),
         :ok <- restart_master_for_scan(scan_start_opts(start_opts)),
         :ok <- EtherCAT.await_running(@scan_await_timeout_ms) do
      {:ok, discovered_slaves(existing_slaves, domains, start_opts)}
    end
  end

  @doc false
  def scan_start_opts(start_opts) when is_list(start_opts) do
    start_opts
    |> Keyword.put(:frame_timeout_ms, @scan_frame_timeout_ms)
    |> Keyword.put(:scan_stable_ms, @scan_stable_ms)
    |> Keyword.put(:scan_poll_ms, @scan_poll_ms)
  end

  @doc false
  def retryable_scan_reason?(reason)

  def retryable_scan_reason?(:timeout), do: true
  def retryable_scan_reason?(:awaiting_preop_timeout), do: true

  def retryable_scan_reason?(reason) when is_tuple(reason) do
    reason
    |> Tuple.to_list()
    |> Enum.any?(&retryable_scan_reason?/1)
  end

  def retryable_scan_reason?(reason) when is_list(reason) do
    Enum.any?(reason, &retryable_scan_reason?/1)
  end

  def retryable_scan_reason?(_reason), do: false

  defp ensure_master_running(start_opts) when is_list(start_opts) do
    case EtherCAT.start(start_opts) do
      :ok -> :ok
      {:error, :already_started} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp restart_master_for_scan(start_opts) when is_list(start_opts) do
    # Rescan should always reflect the current bus/simulator ring, so discovery
    # restarts the temporary master instead of reusing an already running session.
    _ = EtherCAT.stop()
    ensure_master_running(start_opts)
  end

  defp discovered_slaves(existing_slaves, domains, start_opts) do
    existing_by_key =
      Map.new(existing_slaves, fn slave ->
        {slave_lookup_key(slave), slave}
      end)

    default_domain_id = first_domain_id(domains)
    simulator_name_index = simulator_name_index(start_opts)

    slaves =
      case EtherCAT.slaves() do
        {:ok, runtime_slaves} when is_list(runtime_slaves) -> runtime_slaves
        _ -> []
      end

    slaves
    |> Enum.with_index()
    |> Enum.map(fn {%{name: name, station: station}, index} ->
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

      generated_name = to_string(name)
      discovered_name = discovered_name(name, station, index, simulator_name_index)
      existing = matching_existing_slave(existing_by_key, discovered_name, generated_name)

      discovered_slave_entry(
        existing,
        discovered_name,
        station,
        identity,
        driver,
        domains,
        default_domain_id
      )
    end)
    |> normalize_slaves(domains)
  end

  @doc false
  def discovered_name(name, station, index, simulator_name_index)
      when is_atom(name) and is_integer(station) and is_integer(index) and
             is_map(simulator_name_index) do
    station_names = Map.get(simulator_name_index, :by_station, %{})
    ordered_names = Map.get(simulator_name_index, :ordered, [])

    Map.get(station_names, station) || Enum.at(ordered_names, index) || to_string(name)
  end

  @doc false
  def discovered_slave_entry(
        existing,
        discovered_name,
        station,
        identity,
        detected_driver,
        domains,
        default_domain_id
      ) do
    driver = if existing["driver"] in [nil, ""], do: detected_driver, else: existing["driver"]

    %{
      "station" => station,
      "vendor_id" => Map.get(identity, :vendor_id, 0),
      "product_code" => Map.get(identity, :product_code, 0),
      # First discovery inherits the runtime/simulator name, later scans keep user edits.
      "name" => Map.get(existing, "name", discovered_name),
      "discovered_name" => discovered_name,
      "driver" => driver,
      "domain_id" =>
        normalize_domain_id(existing["domain_id"], driver, domains, default_domain_id)
    }
  end

  defp matching_existing_slave(existing_by_key, discovered_name, generated_name)
       when is_map(existing_by_key) do
    Map.get(existing_by_key, discovered_name) || Map.get(existing_by_key, generated_name, %{})
  end

  defp simulator_name_index(start_opts) when is_list(start_opts) do
    with {:ok, %{slaves: slaves} = info} <- EtherCAT.Simulator.info(),
         true <- simulator_matches_start_opts?(info, start_opts) do
      %{
        by_station:
          Map.new(slaves, fn %{station: station, name: name} ->
            {station, to_string(name)}
          end),
        ordered: Enum.map(slaves, &to_string(&1.name))
      }
    else
      _ -> %{by_station: %{}, ordered: []}
    end
  rescue
    _ -> %{by_station: %{}, ordered: []}
  end

  defp payload(assigns) do
    transport = BusSetup.transport_assigns(assigns)

    %{
      transport_mode: Atom.to_string(assigns.transport_mode),
      transport: Atom.to_string(assigns.transport),
      interface: assigns.interface,
      backup_interface: assigns.backup_interface,
      host: assigns.host,
      port: assigns.port,
      transport_source: SetupTransport.summary_label(transport),
      available_interfaces: assigns.available_interfaces,
      status: to_string(assigns.status),
      error: assigns.error,
      slaves: assigns.slaves,
      domains: assigns.domains,
      dc_enabled: assigns.dc_enabled,
      dc_cycle_ns: assigns.dc_cycle_ns,
      await_lock: assigns.await_lock,
      lock_threshold_ns: assigns.lock_threshold_ns,
      lock_timeout_ms: assigns.lock_timeout_ms,
      warmup_cycles: assigns.warmup_cycles,
      master_state: to_string(assigns.master_state),
      master_pid: BusSetup.format_pid(assigns.master_pid),
      available_drivers:
        Enum.map(KinoEtherCAT.Driver.all(), fn %{module: mod, name: name} ->
          %{module: inspect(mod), name: name}
        end)
    }
  end

  defp normalize_attrs(attrs) when is_map(attrs) do
    transport = SetupTransport.normalize(attrs)

    domains =
      attrs
      |> Map.get("domains", legacy_domains(attrs))
      |> normalize_domains()

    %{
      transport_mode: transport.transport_mode,
      transport: transport.transport,
      interface: transport.interface,
      backup_interface: transport.backup_interface,
      host: transport.host,
      port: transport.port,
      domains: domains,
      slaves: attrs |> Map.get("slaves", []) |> normalize_slaves(domains),
      dc_enabled:
        attrs |> Map.get("dc_enabled", Map.get(attrs, "dc_enabled?", false)) |> truthy?(false),
      dc_cycle_ns:
        attrs
        |> Map.get("dc_cycle_ns", default_dc_cycle_ns(domains))
        |> positive_integer(default_dc_cycle_ns(domains)),
      await_lock:
        attrs |> Map.get("await_lock", Map.get(attrs, "await_lock?", false)) |> truthy?(false),
      lock_threshold_ns: attrs |> Map.get("lock_threshold_ns", 100) |> positive_integer(100),
      lock_timeout_ms: attrs |> Map.get("lock_timeout_ms", 5_000) |> positive_integer(5_000),
      warmup_cycles: attrs |> Map.get("warmup_cycles", 0) |> non_negative_integer(0)
    }
  end

  defp normalize_domains(domains) when is_list(domains) do
    normalized =
      domains
      |> Enum.map(&normalize_domain/1)
      |> Enum.reject(&(&1["id"] == ""))
      |> Enum.uniq_by(& &1["id"])

    case normalized do
      [] -> [default_domain()]
      list -> list
    end
  end

  defp normalize_domains(_domains), do: [default_domain()]

  defp normalize_domain(domain) when is_map(domain) do
    cycle_time_ms =
      domain
      |> Map.get("cycle_time_ms", domain_ms_from_legacy(domain))
      |> positive_integer(domain_ms_from_legacy(domain))

    %{
      "id" => domain |> Map.get("id", "") |> String.trim(),
      "cycle_time_ms" => cycle_time_ms,
      "cycle_time_us" => cycle_time_ms * 1_000,
      "miss_threshold" => domain |> Map.get("miss_threshold", 1_000) |> positive_integer(1_000)
    }
  end

  defp normalize_domain(_domain), do: default_domain()

  defp normalize_slaves(slaves, domains) when is_list(slaves) do
    default_domain_id = first_domain_id(domains)

    Enum.map(slaves, fn slave ->
      driver = slave |> Map.get("driver", "") |> normalize_string()

      %{
        "station" => slave |> Map.get("station", 0) |> non_negative_integer(0),
        "vendor_id" => slave |> Map.get("vendor_id", 0) |> non_negative_integer(0),
        "product_code" => slave |> Map.get("product_code", 0) |> non_negative_integer(0),
        "name" => slave |> Map.get("name", "") |> normalize_string(),
        "discovered_name" => slave |> Map.get("discovered_name", "") |> normalize_string(),
        "driver" => driver,
        "domain_id" =>
          normalize_domain_id(Map.get(slave, "domain_id"), driver, domains, default_domain_id)
      }
    end)
  end

  defp normalize_slaves(_slaves, domains), do: normalize_slaves([], domains)

  defp normalize_domain_id(value, driver, domains, default_domain_id) do
    valid_ids = Enum.map(domains, & &1["id"])
    value = normalize_string(value)

    cond do
      driver == "" ->
        ""

      value in valid_ids ->
        value

      default_domain_id in valid_ids ->
        default_domain_id

      true ->
        ""
    end
  end

  defp slave_lookup_key(slave) do
    slave
    |> Map.get("discovered_name", Map.get(slave, "name", ""))
    |> normalize_string()
  end

  defp legacy_domains(attrs) do
    [
      %{
        "id" => Map.get(attrs, "domain_id", "main"),
        "cycle_time_ms" => legacy_cycle_time_ms(attrs),
        "miss_threshold" => 1_000
      }
    ]
  end

  defp default_domain do
    %{
      "id" => "main",
      "cycle_time_ms" => 10,
      "cycle_time_us" => 10_000,
      "miss_threshold" => 1_000
    }
  end

  defp first_domain_id([domain | _rest]), do: domain["id"]
  defp first_domain_id([]), do: ""

  defp default_dc_cycle_ns([domain | _rest]), do: domain["cycle_time_ms"] * 1_000_000
  defp default_dc_cycle_ns([]), do: 10_000_000

  defp domain_ms_from_legacy(domain) do
    domain
    |> Map.get("cycle_time_us", 10_000)
    |> positive_integer(10_000)
    |> Kernel.div(1_000)
    |> max(1)
  end

  defp legacy_cycle_time_ms(attrs) do
    attrs
    |> Map.get("cycle_time_us", 10_000)
    |> positive_integer(10_000)
    |> Kernel.div(1_000)
    |> max(1)
  end

  defp normalize_string(value) when is_binary(value), do: String.trim(value)
  defp normalize_string(_value), do: ""

  defp assign_transport(ctx, transport) do
    assign(ctx,
      transport_mode: transport.transport_mode,
      transport: transport.transport,
      interface: transport.interface,
      backup_interface: transport.backup_interface,
      host: transport.host,
      port: transport.port
    )
  end

  defp simulator_running? do
    match?({:ok, _}, EtherCAT.Simulator.info())
  rescue
    _ -> false
  end

  defp simulator_matches_start_opts?(%{udp: %{ip: host, port: port}}, start_opts) do
    Keyword.get(start_opts, :transport, :raw) == :udp and
      Keyword.get(start_opts, :host) == host and
      Keyword.get(start_opts, :port) == port
  end

  defp simulator_matches_start_opts?(%{raw: %{interface: interface}}, start_opts) do
    interface == SimulatorConfig.raw_simulator_interface() and
      Keyword.get(start_opts, :interface) == SimulatorConfig.raw_master_interface()
  end

  defp simulator_matches_start_opts?(
         %{raw: %{primary: %{interface: primary}, secondary: %{interface: secondary}}},
         start_opts
       ) do
    primary == SimulatorConfig.redundant_simulator_primary_interface() and
      secondary == SimulatorConfig.redundant_simulator_secondary_interface() and
      Keyword.get(start_opts, :interface) == SimulatorConfig.redundant_master_primary_interface() and
      Keyword.get(start_opts, :backup_interface) ==
        SimulatorConfig.redundant_master_secondary_interface()
  end

  defp simulator_matches_start_opts?(_info, _start_opts), do: false

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value

  defp positive_integer(value, default) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> default
    end
  end

  defp positive_integer(_value, default), do: default

  defp non_negative_integer(value, _default) when is_integer(value) and value >= 0, do: value

  defp non_negative_integer(value, default) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed >= 0 -> parsed
      _ -> default
    end
  end

  defp non_negative_integer(_value, default), do: default

  defp truthy?(value, _default) when value in [true, "true"], do: true
  defp truthy?(value, _default) when value in [false, "false"], do: false
  defp truthy?(nil, default), do: default
  defp truthy?(_value, default), do: default
end
