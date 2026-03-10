defmodule KinoEtherCAT.SmartCells.Setup do
  use Kino.JS, assets_path: "lib/assets/setup_cell/build"
  use Kino.JS.Live
  use Kino.SmartCell, name: "EtherCAT Setup"

  alias KinoEtherCAT.SmartCells.SetupSource

  @impl true
  def init(attrs, ctx) do
    config = normalize_attrs(attrs)
    status = if config.slaves == [], do: :idle, else: :discovered
    Process.send_after(self(), :poll_state, 500)

    {:ok,
     assign(ctx,
       status: status,
       error: nil,
       master_state: runtime_state(),
       master_pid: Process.whereis(EtherCAT.Master),
       available_interfaces: available_interfaces(),
       interface: config.interface,
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
    server = self()

    Task.start(fn ->
      run_scan(server, ctx.assigns.interface, ctx.assigns.slaves, ctx.assigns.domains)
    end)

    ctx = assign(ctx, status: :scanning, error: nil)
    broadcast_event(ctx, "snapshot", payload(ctx.assigns))
    {:noreply, ctx}
  end

  def handle_event("stop", _params, ctx) do
    _ = EtherCAT.stop()

    ctx =
      assign(ctx,
        status: :idle,
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
        available_interfaces: available_interfaces(),
        interface: config.interface,
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
  def handle_info({:scan_complete, {:ok, slaves}}, ctx) do
    ctx =
      assign(ctx,
        status: :discovered,
        slaves: slaves,
        error: nil,
        master_state: runtime_state(),
        master_pid: Process.whereis(EtherCAT.Master),
        available_interfaces: available_interfaces()
      )

    broadcast_event(ctx, "snapshot", payload(ctx.assigns))
    {:noreply, ctx}
  end

  def handle_info({:scan_complete, {:error, reason}}, ctx) do
    ctx = assign(ctx, status: :error, error: reason)
    broadcast_event(ctx, "snapshot", payload(ctx.assigns))
    {:noreply, ctx}
  end

  def handle_info(:poll_state, ctx) do
    Process.send_after(self(), :poll_state, 2_000)

    state = runtime_state()
    pid = Process.whereis(EtherCAT.Master)
    interfaces = available_interfaces()

    if state != ctx.assigns.master_state or
         pid != ctx.assigns.master_pid or
         interfaces != ctx.assigns.available_interfaces do
      ctx = assign(ctx, master_state: state, master_pid: pid, available_interfaces: interfaces)
      broadcast_event(ctx, "snapshot", payload(ctx.assigns))
      {:noreply, ctx}
    else
      {:noreply, ctx}
    end
  end

  @impl true
  def to_attrs(ctx) do
    %{
      "interface" => ctx.assigns.interface,
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

  defp run_scan(server, interface, existing_slaves, domains) do
    result =
      with :ok <- ensure_master_running(interface),
           :ok <- EtherCAT.await_running(15_000) do
        {:ok, discovered_slaves(existing_slaves, domains)}
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

  defp discovered_slaves(existing_slaves, domains) do
    existing_by_key =
      Map.new(existing_slaves, fn slave ->
        {slave_lookup_key(slave), slave}
      end)

    default_domain_id = first_domain_id(domains)

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
      existing = Map.get(existing_by_key, discovered_name, %{})
      driver = if existing["driver"] in [nil, ""], do: driver, else: existing["driver"]

      %{
        "station" => station,
        "vendor_id" => Map.get(identity, :vendor_id, 0),
        "product_code" => Map.get(identity, :product_code, 0),
        "name" => Map.get(existing, "name", discovered_name),
        "discovered_name" => discovered_name,
        "driver" => driver,
        "domain_id" =>
          normalize_domain_id(existing["domain_id"], driver, domains, default_domain_id)
      }
    end)
    |> normalize_slaves(domains)
  end

  defp payload(assigns) do
    %{
      interface: assigns.interface,
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
      master_pid: format_pid(assigns.master_pid),
      available_drivers:
        Enum.map(KinoEtherCAT.Driver.all(), fn %{module: mod, name: name} ->
          %{module: inspect(mod), name: name}
        end)
    }
  end

  defp normalize_attrs(attrs) when is_map(attrs) do
    domains =
      attrs
      |> Map.get("domains", legacy_domains(attrs))
      |> normalize_domains()

    %{
      interface: attrs |> Map.get("interface", "eth0") |> normalize_interface(),
      domains: domains,
      slaves: attrs |> Map.get("slaves", []) |> normalize_slaves(domains),
      dc_enabled:
        attrs |> Map.get("dc_enabled", Map.get(attrs, "dc_enabled?", true)) |> truthy?(true),
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

  defp runtime_state do
    case EtherCAT.state() do
      state when is_atom(state) -> state
      _ -> :idle
    end
  rescue
    _ -> :idle
  end

  defp format_pid(pid) when is_pid(pid), do: inspect(pid)
  defp format_pid(_pid), do: nil

  defp normalize_interface(value) when is_binary(value) do
    case String.trim(value) do
      "" -> "eth0"
      trimmed -> trimmed
    end
  end

  defp normalize_interface(_value), do: "eth0"

  defp available_interfaces do
    "/sys/class/net"
    |> File.ls()
    |> case do
      {:ok, interfaces} ->
        interfaces
        |> Enum.reject(&(&1 == "lo"))
        |> Enum.sort()

      {:error, _reason} ->
        []
    end
  end

  defp normalize_string(value) when is_binary(value), do: String.trim(value)
  defp normalize_string(_value), do: ""

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
