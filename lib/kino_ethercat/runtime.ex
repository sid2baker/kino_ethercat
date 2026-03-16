defmodule KinoEtherCAT.Runtime do
  @moduledoc """
  Runtime-facing API for inspecting and controlling EtherCAT resources.

  These functions return EtherCAT structs with enough identifying information
  for `Kino.Render` protocol implementations to build rich Livebook views.
  """

  alias EtherCAT.Domain.Config, as: DomainConfig
  alias EtherCAT.Domain.API, as: DomainAPI
  alias EtherCAT.Slave.API, as: SlaveAPI
  alias EtherCAT.{Domain, Master, Slave}
  alias KinoEtherCAT.Runtime.BusResource
  alias KinoEtherCAT.{StartConfig, WidgetLogs}

  @type log_scope :: :master | :bus | :dc | {:slave, atom()} | {:domain, atom()}

  @spec master() :: %Master{}
  def master do
    case fetch_master_state() do
      {:ok, _state_name, %Master{} = master} -> master
      _ -> struct(Master, activation_phase: :idle)
    end
  end

  @spec slave(atom()) :: %Slave{}
  def slave(name) when is_atom(name) do
    case fetch_slave_state(name) do
      {:ok, _state_name, %Slave{} = slave} -> slave
      _ -> struct(Slave, name: name)
    end
  end

  @spec domain(atom()) :: %Domain{}
  def domain(id) when is_atom(id) do
    case fetch_domain_state(id) do
      {:ok, _state_name, %Domain{} = domain} -> domain
      _ -> struct(Domain, id: id)
    end
  end

  @spec dc() :: struct()
  def dc do
    case fetch_dc_state() do
      {:ok, _state_name, data} when is_struct(data, EtherCAT.DC) ->
        data

      _ ->
        fetch_dc_status()
    end
  end

  @spec bus() :: BusResource.t()
  def bus do
    case current_bus_server() do
      {:ok, bus_server} -> %BusResource{ref: bus_server}
      _ -> %BusResource{ref: nil}
    end
  end

  @spec refresh(struct()) :: struct()
  def refresh(%Master{}), do: master()
  def refresh(%Slave{name: name}), do: slave(name)
  def refresh(%Domain{id: id}), do: domain(id)
  def refresh(%BusResource{}), do: bus()
  def refresh(resource) when is_struct(resource, EtherCAT.DC), do: dc()
  def refresh(resource) when is_struct(resource, EtherCAT.DC.Status), do: dc()

  @doc false
  @spec domain_wkc_display(map()) :: String.t()
  def domain_wkc_display(info) when is_map(info) do
    expected = Map.get(info, :expected_wkc, 0)

    case domain_actual_wkc(info) do
      actual when is_integer(actual) and actual != expected -> "#{actual} / #{expected}"
      _ -> Integer.to_string(expected)
    end
  end

  @doc false
  @spec slave_state_display(atom() | nil, map()) :: String.t()
  def slave_state_display(state_name, info) when is_map(info) do
    state_name
    |> slave_public_state(Map.get(info, :al_state))
    |> to_string()
  end

  @doc false
  @spec slave_transition_options(atom()) :: [String.t()]
  def slave_transition_options(master_state) when master_state in [:operational, :recovering] do
    ["safeop", "op"]
  end

  def slave_transition_options(_master_state), do: ["init", "preop", "safeop", "op"]

  @doc false
  @spec slave_transition_help(atom()) :: String.t() | nil
  def slave_transition_help(master_state) when master_state in [:operational, :recovering] do
    "With the master running, PREOP and INIT do not stick because a slave reaching PREOP is treated as reconnect-ready and is promoted back toward OP."
  end

  def slave_transition_help(_master_state), do: nil

  @spec subscribe_logs(pid(), struct()) :: :ok
  def subscribe_logs(pid, resource) when is_pid(pid) do
    WidgetLogs.subscribe(pid, resource)
  end

  @spec log_scope(struct()) :: log_scope() | nil
  def log_scope(resource) do
    case WidgetLogs.scope(resource) do
      {:ok, scope} -> scope
      :error -> nil
    end
  end

  @spec payload(struct(), map() | nil) :: map()
  def payload(resource, message \\ nil)

  def payload(%Master{} = master, message) do
    public_state = runtime_state(fetch_state_name(master) || :idle)
    remember_start_options(master)
    slaves = runtime_slaves()
    domains = runtime_domains()
    dc_status = dc_snapshot(dc())
    desired_target = master_desired_target(master)
    start_available? = master_start_available?(public_state)
    activation_available? = master_activation_available?(public_state)
    deactivate_safeop_available? = master_deactivate_safeop_available?(public_state)
    deactivate_preop_available? = master_deactivate_preop_available?(public_state)
    stop_available? = master_stop_available?(public_state)

    %{
      kind: "master",
      title: "EtherCAT Master",
      status: to_string(public_state),
      message: message,
      meta_layout: "stacked",
      logs: payload_logs(master),
      log_controls: log_controls(master),
      summary: [
        %{label: "Slaves", value: Integer.to_string(length(slaves))},
        %{label: "Domains", value: Integer.to_string(length(domains))},
        %{label: "Transport", value: master_transport_label()}
      ],
      tables: [],
      details_title: "Session",
      details: master_details(master, desired_target, dc_status),
      controls: %{
        title: "Session",
        buttons:
          master_buttons(
            public_state,
            start_available?,
            activation_available?,
            deactivate_safeop_available?,
            deactivate_preop_available?,
            stop_available?
          ),
        help:
          master_control_help(
            public_state,
            start_available?,
            activation_available?,
            deactivate_safeop_available?,
            deactivate_preop_available?
          )
      }
    }
  end

  def payload(%Slave{name: name} = slave, message) do
    info = safe(fn -> EtherCAT.slave_info(name) end, {:error, :not_found})
    state_name = fetch_state_name(slave)
    master_state = runtime_state(fetch_state_name(%Master{}) || :idle)

    case info do
      {:ok, info} ->
        public_state = slave_state_display(state_name, info)

        signal_rows =
          Enum.map(info.signals, fn signal ->
            %{
              key: "#{signal.direction}:#{signal.name}",
              cells: [
                to_string(signal.name),
                to_string(signal.direction),
                to_string(signal.domain),
                Integer.to_string(signal.bit_size)
              ]
            }
          end)

        %{
          kind: "slave",
          title: "Slave #{name}",
          status: public_state,
          message: message,
          logs: payload_logs(slave),
          log_controls: log_controls(slave),
          summary: [
            %{label: "State", value: public_state},
            %{label: "Station", value: hex(info.station, 4)},
            %{label: "Driver", value: format_term(info.driver)},
            %{label: "AL error", value: format_term(slave.error_code || "none")},
            %{label: "CoE", value: to_string(info.coe)},
            %{label: "Signals", value: Integer.to_string(length(info.signals))},
            %{label: "Log filter", value: Atom.to_string(current_log_level(slave))}
          ],
          tables: [
            %{
              title: "Signals",
              headers: ["Signal", "Direction", "Domain", "Bits"],
              rows: signal_rows
            }
          ],
          details: [
            %{label: "Reported AL state", value: to_string(Map.get(info, :al_state, :unknown))},
            %{label: "Identity", value: format_term(info.identity || %{})},
            %{
              label: "Configuration error",
              value: format_term(info.configuration_error || "none")
            },
            %{label: "Process data", value: format_term(slave.process_data_request || :none)}
          ],
          controls: %{
            select: %{
              id: "transition",
              label: "Transition",
              options: slave_transition_options(master_state)
            },
            help: slave_transition_help(master_state)
          }
        }

      {:error, reason} ->
        unavailable_payload(slave, "slave", "Slave #{name}", reason, message)
    end
  end

  def payload(%Domain{id: id}, message) do
    state_name = fetch_state_name(%Domain{id: id})
    info = safe(fn -> EtherCAT.domain_info(id) end, {:error, :not_found})

    case info do
      {:ok, info} ->
        %{
          kind: "domain",
          title: "Domain #{id}",
          status: to_string(info.state),
          message: message,
          logs: payload_logs(%Domain{id: id}),
          log_controls: log_controls(%Domain{id: id}),
          summary: [
            %{label: "State", value: to_string(state_name || info.state)},
            %{label: "Cycle", value: "#{info.cycle_time_us} us"},
            %{label: "Cycles", value: Integer.to_string(info.cycle_count)},
            %{label: "Misses", value: Integer.to_string(info.miss_count)},
            %{label: "Total misses", value: Integer.to_string(info.total_miss_count)},
            %{label: "WKC", value: domain_wkc_display(info)},
            %{label: "Log filter", value: Atom.to_string(current_log_level(%Domain{id: id}))}
          ],
          tables: [],
          details: [
            %{label: "Health", value: format_term(Map.get(info, :cycle_health, :unknown))},
            %{label: "Image size", value: format_term(Map.get(info, :image_size, "n/a"))},
            %{label: "Expected WKC", value: Integer.to_string(Map.get(info, :expected_wkc, 0))},
            %{
              label: "Last invalid reason",
              value: format_term(Map.get(info, :last_invalid_reason, "none"))
            },
            %{label: "Logical base", value: format_term(runtime_domain(id).logical_base || "n/a")}
          ],
          controls: %{
            buttons: [
              %{id: "start_cycling", label: "Start", tone: "primary"},
              %{id: "stop_cycling", label: "Stop", tone: "danger"}
            ],
            input: %{
              id: "cycle_time_us",
              label: "Update cycle (us)",
              value: Integer.to_string(info.cycle_time_us)
            },
            submit: %{id: "update_cycle_time", label: "Apply cycle"}
          }
        }

      {:error, reason} ->
        unavailable_payload(%Domain{id: id}, "domain", "Domain #{id}", reason, message)
    end
  end

  def payload(%BusResource{} = bus, message) do
    info = current_bus_info(bus)
    state_name = Map.get(info, :state, :not_started)
    queue_depths = queue_depths(info)
    frame_timeout_ms = Map.get(info, :frame_timeout_ms, 25)
    timeout_count = Map.get(info, :timeout_count, 0)

    %{
      kind: "bus",
      title: "Bus",
      status: to_string(state_name || :not_started),
      message: message,
      logs: payload_logs(bus),
      log_controls: log_controls(bus),
      summary: [
        %{label: "Frame timeout", value: "#{frame_timeout_ms} ms"},
        %{label: "Timeouts", value: Integer.to_string(timeout_count)},
        %{label: "Realtime queue", value: Integer.to_string(queue_depths.realtime)},
        %{label: "Reliable queue", value: Integer.to_string(queue_depths.reliable)},
        %{label: "Link", value: format_term(Map.get(info, :link, "none"))},
        %{label: "Log filter", value: Atom.to_string(current_log_level(bus))}
      ],
      tables: [],
      details: [
        %{label: "Topology", value: format_term(Map.get(info, :topology, "unknown"))},
        %{label: "Fault", value: format_term(Map.get(info, :fault, "none"))},
        %{label: "Carrier up", value: format_term(Map.get(info, :carrier_up, "n/a"))},
        %{label: "Circuit", value: format_term(Map.get(info, :circuit_info, "none"))},
        %{
          label: "Last observation",
          value: format_term(Map.get(info, :last_observation, "none"))
        },
        %{label: "In flight", value: format_term(Map.get(info, :in_flight, "none"))},
        %{label: "Last error", value: format_term(Map.get(info, :last_error_reason, "none"))}
      ],
      controls: %{
        input: %{
          id: "frame_timeout_ms",
          label: "Frame timeout (ms)",
          value: Integer.to_string(frame_timeout_ms)
        },
        submit: %{id: "set_frame_timeout", label: "Apply timeout", tone: "primary"}
      }
    }
  end

  def payload(resource, message) when is_struct(resource, EtherCAT.DC) do
    payload_dc_resource(resource, message)
  end

  def payload(resource, message) when is_struct(resource, EtherCAT.DC.Status) do
    payload_dc_resource(resource, message)
  end

  @doc false
  @spec start_options_from_runtime(Master.t(), BusResource.t() | map()) ::
          {:ok, keyword()} | :error
  def start_options_from_runtime(%Master{} = master, bus_resource) do
    with {:ok, bus_info} <- bus_info(bus_resource),
         bus_opts when is_list(bus_opts) and bus_opts != [] <- bus_start_opts(bus_info) do
      {:ok,
       bus_opts
       |> Keyword.put(:slaves, master.slave_configs || [])
       |> Keyword.put(:domains, domain_configs(master.domain_configs || []))
       |> Keyword.put(:base_station, master.base_station || 0x1000)
       |> Keyword.put(:dc, master.dc_config)
       |> Keyword.put(:scan_poll_ms, master.scan_poll_ms || 100)
       |> Keyword.put(:scan_stable_ms, master.scan_stable_ms || 1_000)
       |> maybe_put_start_opt(:frame_timeout_ms, master.frame_timeout_override_ms)}
    else
      _ -> :error
    end
  end

  defp payload_dc_resource(resource, message) do
    status = dc_snapshot(resource)

    %{
      kind: "dc",
      title: "Distributed Clocks",
      status: to_string(status.lock_state),
      message: message,
      logs: payload_logs(resource),
      log_controls: log_controls(resource),
      summary: [
        %{label: "Configured", value: to_string(status.configured?)},
        %{label: "Active", value: to_string(status.active?)},
        %{
          label: "Reference",
          value: format_term(status.reference_clock || status.reference_station || "none")
        },
        %{label: "Cycle", value: format_term(status.cycle_ns || "n/a")},
        %{label: "Max diff", value: format_term(status.max_sync_diff_ns || "n/a")}
      ],
      tables: [],
      details: [
        %{label: "Reference station", value: format_term(status.reference_station || "none")},
        %{label: "Monitored stations", value: format_term(status.monitored_stations || [])},
        %{label: "Cycle count", value: format_term(status.cycle_count || "n/a")},
        %{label: "Last sync check", value: format_term(status.last_sync_check_at_ms || "none")},
        %{label: "Monitor failures", value: Integer.to_string(status.monitor_failures || 0)},
        %{label: "Tick interval", value: format_term(status.tick_interval_ms || "n/a")},
        %{
          label: "Diagnostic cadence",
          value: format_term(status.diagnostic_interval_cycles || "n/a")
        },
        %{label: "Bus", value: format_term(status.bus || "none")},
        %{label: "Log filter", value: Atom.to_string(current_log_level(resource))}
      ],
      controls: %{
        input: %{id: "timeout_ms", label: "Await lock (ms)", value: "5000"},
        submit: %{id: "await_dc_locked", label: "Await lock", tone: "primary"}
      }
    }
  end

  @spec perform(struct(), String.t(), map()) :: {:ok, struct(), map()} | {:error, struct(), map()}
  def perform(resource, action, params \\ %{})

  def perform(resource, "refresh", _params) do
    refreshed = refresh(resource)
    {:ok, refreshed, info_message("Refreshed")}
  end

  def perform(%Master{} = resource, "start", _params) do
    with opts when is_list(opts) <- StartConfig.current() do
      run_action(resource, fn -> EtherCAT.start(opts) end, "Master start requested")
    else
      _ -> {:error, resource, error_message(:missing_start_config)}
    end
  end

  def perform(%Master{} = resource, "activate", _params) do
    run_action(resource, fn -> EtherCAT.activate() end, "Master activated")
  end

  def perform(%Master{} = resource, "deactivate_safeop", _params) do
    run_action(resource, fn -> EtherCAT.deactivate() end, "Master deactivated to SAFEOP")
  end

  def perform(%Master{} = resource, "deactivate_preop", _params) do
    run_action(resource, fn -> EtherCAT.deactivate(:preop) end, "Master deactivated to PREOP")
  end

  def perform(%Master{} = resource, "stop", _params) do
    run_action(resource, fn -> EtherCAT.stop() end, "Master stopped")
  end

  def perform(resource, "set_log_level", %{"value" => value}) do
    with {:ok, level} <- parse_log_level(value) do
      run_action(
        resource,
        fn -> WidgetLogs.set_level(resource, level) end,
        "Log filter set to #{level}"
      )
    else
      {:error, reason} -> {:error, resource, error_message(reason)}
    end
  end

  def perform(resource, "clear_logs", _params) do
    run_action(resource, fn -> WidgetLogs.clear(resource) end, "Logs cleared")
  end

  def perform(%Slave{name: name} = resource, "transition", %{"value" => target}) do
    with {:ok, target} <- transition_target(target) do
      run_action(
        resource,
        fn -> SlaveAPI.request(name, target) end,
        "Slave transitioned to #{target}"
      )
    else
      {:error, reason} -> {:error, resource, error_message(reason)}
    end
  end

  def perform(%Domain{id: id} = resource, "start_cycling", _params) do
    run_action(resource, fn -> DomainAPI.start_cycling(id) end, "Domain cycling started")
  end

  def perform(%Domain{id: id} = resource, "stop_cycling", _params) do
    run_action(resource, fn -> DomainAPI.stop_cycling(id) end, "Domain cycling stopped")
  end

  def perform(%Domain{id: id} = resource, "update_cycle_time", %{"value" => value}) do
    with {:ok, cycle_time_us} <- parse_positive_integer(value) do
      run_action(
        resource,
        fn -> EtherCAT.update_domain_cycle_time(id, cycle_time_us) end,
        "Domain cycle updated to #{cycle_time_us} us"
      )
    else
      {:error, reason} -> {:error, resource, error_message(reason)}
    end
  end

  def perform(%BusResource{} = resource, "set_frame_timeout", %{"value" => value}) do
    with {:ok, timeout_ms} <- parse_positive_integer(value),
         {:ok, bus} <- bus_server(resource) do
      run_action(
        resource,
        fn -> EtherCAT.Bus.set_frame_timeout(bus, timeout_ms) end,
        "Frame timeout set to #{timeout_ms} ms"
      )
    else
      {:error, reason} -> {:error, resource, error_message(reason)}
    end
  end

  def perform(resource, "await_dc_locked", %{"value" => value})
      when is_struct(resource, EtherCAT.DC) or is_struct(resource, EtherCAT.DC.Status) do
    with {:ok, timeout_ms} <- parse_positive_integer(value) do
      run_action(resource, fn -> EtherCAT.await_dc_locked(timeout_ms) end, "DC locked")
    else
      {:error, reason} -> {:error, resource, error_message(reason)}
    end
  end

  def perform(resource, _action, _params),
    do: {:error, resource, error_message(:unsupported_action)}

  defp safe(fun, default) do
    fun.()
  rescue
    _ -> default
  catch
    :exit, _ -> default
  end

  defp fetch_master_state do
    fetch_statem_state(EtherCAT.Master)
  end

  defp fetch_slave_state(name) when is_atom(name) do
    fetch_registry_statem_state({:slave, name})
  end

  defp fetch_domain_state(id) when is_atom(id) do
    fetch_registry_statem_state({:domain, id})
  end

  defp fetch_dc_state do
    case Process.whereis(EtherCAT.DC) do
      nil -> {:error, :not_started}
      _pid -> fetch_statem_state(EtherCAT.DC)
    end
  end

  defp fetch_statem_state(server) do
    try do
      case :sys.get_state(server) do
        {state_name, data} -> {:ok, state_name, data}
        data -> {:ok, nil, data}
      end
    catch
      :exit, {:noproc, _} -> {:error, :not_started}
      :exit, {:normal, _} -> {:error, :not_started}
      :exit, reason -> {:error, reason}
    end
  end

  defp fetch_registry_statem_state(key) do
    if Process.whereis(EtherCAT.Registry) do
      fetch_statem_state({:via, Registry, {EtherCAT.Registry, key}})
    else
      {:error, :not_started}
    end
  end

  defp fetch_state_name(%Master{}) do
    case fetch_master_state() do
      {:ok, state_name, _master} -> state_name
      _ -> nil
    end
  end

  defp fetch_state_name(%Slave{name: name}) when is_atom(name) do
    case fetch_slave_state(name) do
      {:ok, state_name, _slave} -> state_name
      _ -> nil
    end
  end

  defp fetch_state_name(%Domain{id: id}) when is_atom(id) do
    case fetch_domain_state(id) do
      {:ok, state_name, _domain} -> state_name
      _ -> nil
    end
  end

  defp runtime_domain(id) when is_atom(id) do
    case fetch_domain_state(id) do
      {:ok, _state_name, %Domain{} = domain} -> domain
      _ -> %Domain{id: id}
    end
  end

  defp runtime_slaves do
    case safe(fn -> EtherCAT.slaves() end, []) do
      {:ok, slaves} when is_list(slaves) -> slaves
      _ -> []
    end
  end

  defp runtime_domains do
    case safe(fn -> EtherCAT.domains() end, []) do
      {:ok, domains} when is_list(domains) -> domains
      _ -> []
    end
  end

  defp runtime_state(default) do
    case safe(fn -> EtherCAT.state() end, default) do
      {:ok, state} when is_atom(state) -> state
      _ -> default
    end
  end

  defp fetch_dc_status do
    case safe(fn -> EtherCAT.dc_status() end, nil) do
      {:ok, resource} when is_struct(resource, EtherCAT.DC) ->
        resource

      {:ok, resource} when is_struct(resource, EtherCAT.DC.Status) ->
        resource

      _ ->
        default_dc_resource()
    end
  end

  defp current_bus_server do
    case safe(fn -> EtherCAT.bus() end, nil) do
      {:ok, nil} -> {:error, :not_started}
      {:ok, bus_server} -> {:ok, bus_server}
      {:error, _} = error -> error
      nil -> {:error, :not_started}
      _ -> {:error, :not_started}
    end
  end

  defp bus_server(%BusResource{ref: ref}) when not is_nil(ref), do: {:ok, ref}
  defp bus_server(%BusResource{}), do: current_bus_server()

  defp bus_info(%BusResource{} = resource) do
    with {:ok, bus_server} <- bus_server(resource) do
      case safe(fn -> EtherCAT.Bus.info(bus_server) end, {:error, :not_started}) do
        {:ok, info} when is_map(info) -> {:ok, info}
        _ -> :error
      end
    else
      _ -> :error
    end
  end

  defp bus_info(info) when is_map(info), do: {:ok, info}
  defp bus_info(_resource), do: :error

  defp current_bus_info(%BusResource{} = resource) do
    case bus_info(resource) do
      {:ok, info} -> info
      :error -> %{}
    end
  end

  defp default_dc_resource do
    cond do
      Code.ensure_loaded?(EtherCAT.DC.Status) and
          function_exported?(EtherCAT.DC.Status, :__struct__, 0) ->
        struct(EtherCAT.DC.Status)

      Code.ensure_loaded?(EtherCAT.DC) and function_exported?(EtherCAT.DC, :__struct__, 0) ->
        struct(EtherCAT.DC)

      true ->
        %{}
    end
  end

  defp dc_snapshot(resource) when is_struct(resource, EtherCAT.DC) do
    config = Map.get(resource, :config, %{})

    %{
      configured?: not is_nil(Map.get(resource, :config)),
      active?: Map.get(resource, :cycle_count, 0) > 0,
      lock_state: Map.get(resource, :lock_state, :unknown),
      reference_clock: nil,
      reference_station: Map.get(resource, :ref_station),
      cycle_ns: Map.get(config, :cycle_ns),
      max_sync_diff_ns: Map.get(resource, :max_sync_diff_ns),
      last_sync_check_at_ms: Map.get(resource, :last_sync_check_at_ms),
      monitor_failures: Map.get(resource, :fail_count, 0),
      cycle_count: Map.get(resource, :cycle_count, 0),
      monitored_stations: Map.get(resource, :monitored_stations, []),
      tick_interval_ms: Map.get(resource, :tick_interval_ms),
      diagnostic_interval_cycles: Map.get(resource, :diagnostic_interval_cycles),
      bus: Map.get(resource, :bus)
    }
  end

  defp dc_snapshot(resource) when is_struct(resource, EtherCAT.DC.Status) do
    %{
      configured?: Map.get(resource, :configured?, false),
      active?: Map.get(resource, :active?, false),
      lock_state: Map.get(resource, :lock_state, :disabled),
      reference_clock: Map.get(resource, :reference_clock),
      reference_station: Map.get(resource, :reference_station),
      cycle_ns: Map.get(resource, :cycle_ns),
      max_sync_diff_ns: Map.get(resource, :max_sync_diff_ns),
      last_sync_check_at_ms: Map.get(resource, :last_sync_check_at_ms),
      monitor_failures: Map.get(resource, :monitor_failures, 0),
      cycle_count: nil,
      monitored_stations: [],
      tick_interval_ms: nil,
      diagnostic_interval_cycles: nil,
      bus: nil
    }
  end

  defp run_action(resource, fun, success_label) do
    case fun.() do
      :ok ->
        refreshed = refresh(resource)
        {:ok, refreshed, info_message(success_label)}

      :already_stopped ->
        {:ok, refresh(resource), info_message("Master already stopped")}

      {:ok, _} ->
        refreshed = refresh(resource)
        {:ok, refreshed, info_message(success_label)}

      {:error, reason} ->
        {:error, refresh(resource), error_message(reason)}
    end
  rescue
    error ->
      {:error, refresh(resource), error_message(Exception.message(error))}
  end

  defp transition_target(target) when target in ["init", "preop", "safeop", "op"] do
    {:ok, String.to_existing_atom(target)}
  end

  defp transition_target(_target), do: {:error, :invalid_transition}

  defp parse_log_level("debug"), do: {:ok, :debug}
  defp parse_log_level("info"), do: {:ok, :info}
  defp parse_log_level("notice"), do: {:ok, :notice}
  defp parse_log_level("warning"), do: {:ok, :warning}
  defp parse_log_level("error"), do: {:ok, :error}
  defp parse_log_level("critical"), do: {:ok, :critical}
  defp parse_log_level("alert"), do: {:ok, :alert}
  defp parse_log_level("emergency"), do: {:ok, :emergency}
  defp parse_log_level("none"), do: {:ok, :none}
  defp parse_log_level("all"), do: {:ok, :all}
  defp parse_log_level(_target), do: {:error, :invalid_log_level}

  defp parse_positive_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} when int > 0 -> {:ok, int}
      _ -> {:error, :invalid_integer}
    end
  end

  defp parse_positive_integer(_value), do: {:error, :invalid_integer}

  defp unavailable_payload(resource, kind, title, reason, message) do
    %{
      kind: kind,
      title: title,
      status: "unavailable",
      message: message || error_message(reason),
      logs: payload_logs(resource),
      log_controls: log_controls(resource),
      summary: [],
      tables: [],
      details: [%{label: "Reason", value: format_term(reason)}],
      controls: nil
    }
  end

  defp info_message(text), do: %{level: "info", text: text}
  defp error_message(reason), do: %{level: "error", text: format_term(reason)}

  defp payload_logs(resource) do
    resource
    |> WidgetLogs.entries()
    |> Enum.map(fn entry ->
      %{
        id: entry.id,
        time: format_log_time(entry.at_ms),
        level: entry.level,
        text: entry.text
      }
    end)
  end

  defp current_log_level(resource), do: WidgetLogs.level(resource)

  defp slave_public_state(state_name, _al_state)
       when is_atom(state_name) and not is_nil(state_name),
       do: state_name

  defp slave_public_state(_state_name, al_state) when is_atom(al_state) and not is_nil(al_state),
    do: al_state

  defp slave_public_state(_state_name, _al_state), do: :unknown

  defp domain_actual_wkc(%{cycle_health: {:invalid, {:wkc_mismatch, %{actual: actual}}}})
       when is_integer(actual),
       do: actual

  defp domain_actual_wkc(_info), do: nil

  defp log_level_options do
    [:all, :debug, :info, :notice, :warning, :error, :critical, :alert, :emergency, :none]
  end

  defp log_level_control(resource) do
    %{
      id: "set_log_level",
      label: "Log filter",
      options: Enum.map(log_level_options(), &Atom.to_string/1),
      value: Atom.to_string(current_log_level(resource))
    }
  end

  defp log_controls(resource) do
    %{
      select: log_level_control(resource),
      buttons: [%{id: "clear_logs", label: "Clear logs", tone: "secondary"}]
    }
  end

  defp remember_start_options(%Master{} = master) do
    case start_options_from_runtime(master, bus()) do
      {:ok, opts} -> StartConfig.remember(opts)
      :error -> :ok
    end
  end

  defp bus_start_opts(%{circuit_info: %{type: :single, port: port_info}})
       when is_map(port_info) do
    case port_info do
      %{interface: interface} when is_binary(interface) and byte_size(interface) > 0 ->
        [interface: interface]

      %{name: name} ->
        udp_start_opts(name)

      _ ->
        []
    end
  end

  defp bus_start_opts(%{
         circuit_info: %{
           type: :redundant,
           primary: %{interface: interface},
           secondary: %{interface: backup_interface}
         }
       })
       when is_binary(interface) and is_binary(backup_interface) do
    [interface: interface, backup_interface: backup_interface]
  end

  defp bus_start_opts(_bus_info), do: []

  defp domain_configs(domain_plans) do
    Enum.map(domain_plans, fn plan ->
      %DomainConfig{
        id: plan.id,
        cycle_time_us: plan.cycle_time_us,
        miss_threshold: plan.miss_threshold
      }
    end)
  end

  defp maybe_put_start_opt(opts, _key, nil), do: opts
  defp maybe_put_start_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp udp_transport_opts?(opts) when is_list(opts) do
    Keyword.get(opts, :transport) == :udp or
      Keyword.get(opts, :transport_mod) == EtherCAT.Bus.Transport.UdpSocket
  end

  defp master_desired_target(%Master{} = master) do
    case Map.get(master, :desired_runtime_target, :op) do
      target when target in [:op, :safeop, :preop] -> target
      _ -> :op
    end
  end

  defp master_details(%Master{} = master, desired_target, dc_status) do
    [
      %{label: "Desired target", value: Atom.to_string(desired_target)},
      maybe_detail("DC lock", dc_lock_value(dc_status)),
      maybe_detail("Last failure", last_failure_value(master.last_failure))
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp dc_lock_value(%{lock_state: :disabled}), do: nil
  defp dc_lock_value(%{lock_state: nil}), do: nil
  defp dc_lock_value(%{lock_state: lock_state}), do: to_string(lock_state)
  defp dc_lock_value(_status), do: nil

  defp last_failure_value(nil), do: nil
  defp last_failure_value(:none), do: nil
  defp last_failure_value(value), do: format_term(value)

  defp master_transport_label do
    case bus_info(bus()) do
      {:ok, bus_info} ->
        case bus_start_opts(bus_info) do
          [] -> transport_label(StartConfig.current() || [])
          opts -> transport_label(opts)
        end

      :error ->
        transport_label(StartConfig.current() || [])
    end
  end

  defp transport_label(opts) when is_list(opts) do
    cond do
      udp_transport_opts?(opts) ->
        udp_transport_label(opts)

      interface = Keyword.get(opts, :interface) ->
        redundant_transport_label(interface, Keyword.get(opts, :backup_interface))

      true ->
        "unconfigured"
    end
  end

  defp transport_label(_opts), do: "unconfigured"

  defp udp_transport_label(opts) do
    host = opts |> Keyword.get(:host) |> format_ip()
    port = Keyword.get(opts, :port)

    case {host, port} do
      {host, port} when is_binary(host) and is_integer(port) -> "#{host}:#{port}"
      {host, _port} when is_binary(host) -> host
      _ -> "udp"
    end
  end

  defp redundant_transport_label(interface, backup_interface) when is_binary(backup_interface),
    do: "#{interface} + #{backup_interface}"

  defp redundant_transport_label(interface, _backup_interface), do: interface

  defp format_ip({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"
  defp format_ip({_, _, _, _, _, _, _, _} = ip), do: ip |> :inet.ntoa() |> to_string()
  defp format_ip(ip) when is_binary(ip), do: ip
  defp format_ip(_ip), do: nil

  defp udp_start_opts(name) when is_binary(name) do
    case Regex.run(~r/^(.*):(\d+)$/, String.trim(name), capture: :all_but_first) do
      [host, port] ->
        [transport: :udp, host: parse_ip(host), port: String.to_integer(port)]

      _ ->
        [transport: :udp]
    end
  end

  defp parse_ip(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, ip} -> ip
      {:error, _} -> host
    end
  end

  defp master_start_available?(:idle), do: StartConfig.available?()
  defp master_start_available?(_state), do: false

  defp master_activation_available?(state), do: state in [:preop_ready, :deactivated]

  defp master_deactivate_safeop_available?(state),
    do: state in [:operational, :activation_blocked, :recovering]

  defp master_deactivate_preop_available?(state),
    do: state in [:operational, :activation_blocked, :recovering, :deactivated]

  defp master_stop_available?(:idle), do: false
  defp master_stop_available?(_state), do: true

  defp master_start_title(true), do: "Start the remembered EtherCAT session"

  defp master_start_title(false),
    do: "Start becomes available after EtherCAT has been started with notebook config"

  defp master_buttons(
         :idle,
         start_available?,
         _activation_available?,
         _deactivate_safeop_available?,
         _deactivate_preop_available?,
         _stop_available?
       ) do
    [
      %{
        id: "start",
        label: "Start session",
        tone: "primary",
        disabled: not start_available?,
        title: master_start_title(start_available?)
      }
    ]
  end

  defp master_buttons(
         _state,
         _start_available?,
         true,
         deactivate_safeop_available?,
         deactivate_preop_available?,
         stop_available?
       ) do
    [
      %{id: "activate", label: "Activate OP", tone: "primary"},
      maybe_button(
        %{id: "deactivate_safeop", label: "Deactivate SAFEOP", tone: "secondary"},
        deactivate_safeop_available?
      ),
      maybe_button(
        %{id: "deactivate_preop", label: "Deactivate PREOP", tone: "secondary"},
        deactivate_preop_available?
      ),
      %{id: "stop", label: "Stop session", tone: "danger", disabled: not stop_available?}
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp master_buttons(
         _state,
         _start_available?,
         _activation_available?,
         deactivate_safeop_available?,
         deactivate_preop_available?,
         stop_available?
       ) do
    [
      maybe_button(
        %{id: "deactivate_safeop", label: "Deactivate SAFEOP", tone: "secondary"},
        deactivate_safeop_available?
      ),
      maybe_button(
        %{id: "deactivate_preop", label: "Deactivate PREOP", tone: "secondary"},
        deactivate_preop_available?
      ),
      %{id: "stop", label: "Stop session", tone: "danger", disabled: not stop_available?}
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp master_control_help(
         :idle,
         true,
         _activation_available?,
         _safeop_available?,
         _preop_available?
       ) do
    "Start replays the remembered notebook configuration for this EtherCAT session."
  end

  defp master_control_help(
         :idle,
         false,
         _activation_available?,
         _safeop_available?,
         _preop_available?
       ) do
    "Start becomes available after EtherCAT has been started once from notebook configuration."
  end

  defp master_control_help(
         _state,
         _start_available?,
         true,
         _safeop_available?,
         _preop_available?
       ) do
    "Activate is available because the master is ready to request OP."
  end

  defp master_control_help(_state, _start_available?, false, true, true) do
    "Use Deactivate to settle the session below OP without tearing it down, or Stop to end it completely."
  end

  defp master_control_help(_state, _start_available?, false, true, false) do
    "Use Deactivate SAFEOP to keep the session live below OP, or Stop to end it completely."
  end

  defp master_control_help(_state, _start_available?, false, false, true) do
    "Use Deactivate PREOP for reconfiguration without a full stop, or Stop to end the session completely."
  end

  defp master_control_help(_state, _start_available?, false, false, false) do
    "Use Stop to tear down the current EtherCAT runtime."
  end

  defp maybe_button(button, true), do: button
  defp maybe_button(_button, false), do: nil

  defp maybe_detail(_label, nil), do: nil
  defp maybe_detail(label, value), do: %{label: label, value: value}

  defp format_term(value) when is_binary(value), do: value
  defp format_term(value), do: inspect(value, pretty: false, limit: 20)

  defp format_log_time(at_ms) when is_integer(at_ms) do
    case DateTime.from_unix(at_ms, :millisecond) do
      {:ok, datetime} ->
        milliseconds = at_ms |> rem(1_000) |> Integer.to_string() |> String.pad_leading(3, "0")
        Calendar.strftime(datetime, "%H:%M:%S") <> "." <> milliseconds

      {:error, _reason} ->
        Integer.to_string(at_ms)
    end
  end

  defp hex(nil, _pad), do: "n/a"

  defp hex(value, pad),
    do: "0x" <> String.upcase(String.pad_leading(Integer.to_string(value, 16), pad, "0"))

  defp queue_depths(%{queue_depths: queue_depths}) when is_map(queue_depths) do
    %{
      realtime: Map.get(queue_depths, :realtime, 0),
      reliable: Map.get(queue_depths, :reliable, 0)
    }
  end

  defp queue_depths(_info), do: %{realtime: 0, reliable: 0}
end
