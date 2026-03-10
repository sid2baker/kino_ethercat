defmodule KinoEtherCAT.Runtime do
  @moduledoc """
  Runtime-facing API for inspecting and controlling EtherCAT resources.

  These functions return EtherCAT structs with enough identifying information
  for `Kino.Render` protocol implementations to build rich Livebook views.
  """

  alias EtherCAT.Domain.API, as: DomainAPI
  alias EtherCAT.Slave.API, as: SlaveAPI
  alias EtherCAT.{Bus, Domain, Master, Slave}
  alias KinoEtherCAT.WidgetLogs

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

  @spec bus() :: %Bus{}
  def bus do
    case fetch_bus_state() do
      {:ok, _state_name, %Bus{} = bus} -> bus
      _ -> struct(Bus)
    end
  end

  @spec refresh(struct()) :: struct()
  def refresh(%Master{}), do: master()
  def refresh(%Slave{name: name}), do: slave(name)
  def refresh(%Domain{id: id}), do: domain(id)
  def refresh(%Bus{}), do: bus()
  def refresh(resource) when is_struct(resource, EtherCAT.DC), do: dc()
  def refresh(resource) when is_struct(resource, EtherCAT.DC.Status), do: dc()

  @spec subscribe_logs(pid(), struct()) :: :ok
  def subscribe_logs(pid, resource) when is_pid(pid) do
    WidgetLogs.subscribe(pid, resource)
  end

  @spec log_scope(struct()) :: WidgetLogs.scope() | nil
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
    slaves = runtime_slaves()
    domains = runtime_domains()
    dc_status = dc_snapshot(dc())

    slave_rows =
      Enum.map(slaves, fn %{name: name, station: station} ->
        info = safe(fn -> EtherCAT.slave_info(name) end, {:error, :not_found})

        al_state =
          if match?({:ok, _}, info),
            do: info |> elem(1) |> Map.get(:al_state, :unknown),
            else: :unknown

        %{
          key: Atom.to_string(name),
          cells: [
            Atom.to_string(name),
            hex(station, 4),
            to_string(al_state)
          ]
        }
      end)

    domain_rows =
      Enum.map(domains, fn {id, cycle_time_us, _pid} ->
        info = safe(fn -> EtherCAT.domain_info(id) end, {:error, :not_found})

        state =
          if match?({:ok, _}, info),
            do: info |> elem(1) |> Map.get(:state, :unknown),
            else: :unknown

        %{
          key: Atom.to_string(id),
          cells: [
            Atom.to_string(id),
            "#{cycle_time_us} us",
            to_string(state)
          ]
        }
      end)

    %{
      kind: "master",
      title: "EtherCAT Master",
      status: to_string(public_state),
      message: message,
      logs: payload_logs(master),
      summary: [
        %{label: "State", value: to_string(public_state)},
        %{label: "Slaves", value: Integer.to_string(length(slaves))},
        %{label: "Domains", value: Integer.to_string(length(domains))},
        %{label: "DC lock", value: to_string(dc_status.lock_state || :disabled)},
        %{label: "Log level", value: Atom.to_string(current_log_level(master))},
        %{
          label: "Pending PREOP",
          value: Integer.to_string(MapSet.size(master.pending_preop || MapSet.new()))
        },
        %{label: "Activatable", value: Integer.to_string(length(master.activatable_slaves || []))}
      ],
      tables: [
        %{title: "Slaves", headers: ["Name", "Station", "State"], rows: slave_rows},
        %{title: "Domains", headers: ["Domain", "Cycle", "State"], rows: domain_rows}
      ],
      details: [
        %{label: "Bus monitor", value: format_term(master.bus_ref || "none")},
        %{label: "DC reference station", value: format_term(master.dc_ref_station || "none")},
        %{label: "Last failure", value: format_term(master.last_failure || "none")}
      ],
      controls: %{
        buttons: [
          %{id: "refresh", label: "Refresh", tone: "secondary"},
          %{id: "activate", label: "Activate", tone: "primary"},
          %{id: "stop", label: "Stop", tone: "danger"}
        ],
        log_select: log_level_control(master)
      }
    }
  end

  def payload(%Slave{name: name} = slave, message) do
    info = safe(fn -> EtherCAT.slave_info(name) end, {:error, :not_found})
    state_name = fetch_state_name(slave)

    case info do
      {:ok, info} ->
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
          status: to_string(info.al_state),
          message: message,
          logs: payload_logs(slave),
          summary: [
            %{label: "State", value: to_string(state_name || info.al_state)},
            %{label: "Station", value: hex(info.station, 4)},
            %{label: "Driver", value: format_term(info.driver)},
            %{label: "AL error", value: format_term(slave.error_code || "none")},
            %{label: "CoE", value: to_string(info.coe)},
            %{label: "Signals", value: Integer.to_string(length(info.signals))},
            %{label: "Log level", value: Atom.to_string(current_log_level(slave))}
          ],
          tables: [
            %{
              title: "Signals",
              headers: ["Signal", "Direction", "Domain", "Bits"],
              rows: signal_rows
            }
          ],
          details: [
            %{label: "Identity", value: format_term(info.identity || %{})},
            %{
              label: "Configuration error",
              value: format_term(info.configuration_error || "none")
            },
            %{label: "Process data", value: format_term(slave.process_data_request || :none)}
          ],
          controls: %{
            buttons: [%{id: "refresh", label: "Refresh", tone: "secondary"}],
            select: %{id: "transition", label: "Transition", options: ~w(init preop safeop op)},
            log_select: log_level_control(slave)
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
          summary: [
            %{label: "State", value: to_string(state_name || info.state)},
            %{label: "Cycle", value: "#{info.cycle_time_us} us"},
            %{label: "Cycles", value: Integer.to_string(info.cycle_count)},
            %{label: "Misses", value: Integer.to_string(info.miss_count)},
            %{label: "Total misses", value: Integer.to_string(info.total_miss_count)},
            %{label: "WKC", value: Integer.to_string(info.expected_wkc)},
            %{label: "Log level", value: Atom.to_string(current_log_level(%Domain{id: id}))}
          ],
          tables: [],
          details: [
            %{label: "Health", value: format_term(Map.get(info, :cycle_health, :unknown))},
            %{label: "Image size", value: format_term(Map.get(info, :image_size, "n/a"))},
            %{label: "Logical base", value: format_term(runtime_domain(id).logical_base || "n/a")}
          ],
          controls: %{
            buttons: [
              %{id: "refresh", label: "Refresh", tone: "secondary"},
              %{id: "start_cycling", label: "Start", tone: "primary"},
              %{id: "stop_cycling", label: "Stop", tone: "danger"}
            ],
            log_select: log_level_control(%Domain{id: id}),
            input: %{
              id: "cycle_time_us",
              label: "Update cycle (us)",
              value: Integer.to_string(info.cycle_time_us)
            }
          }
        }

      {:error, reason} ->
        unavailable_payload(%Domain{id: id}, "domain", "Domain #{id}", reason, message)
    end
  end

  def payload(%Bus{} = bus, message) do
    state_name = fetch_state_name(bus)
    queue_depths = queue_depths(bus)

    %{
      kind: "bus",
      title: "Bus",
      status: to_string(state_name || :not_started),
      message: message,
      logs: payload_logs(bus),
      summary: [
        %{label: "Frame timeout", value: "#{bus.frame_timeout_ms || 25} ms"},
        %{label: "Timeouts", value: Integer.to_string(bus.timeout_count || 0)},
        %{label: "Realtime queue", value: Integer.to_string(queue_depths.realtime)},
        %{label: "Reliable queue", value: Integer.to_string(queue_depths.reliable)},
        %{label: "Index", value: Integer.to_string(bus.idx || 0)},
        %{label: "Log level", value: Atom.to_string(current_log_level(bus))}
      ],
      tables: [],
      details: [
        %{label: "Link module", value: format_term(bus.link_mod || "none")},
        %{label: "Link", value: format_term(bus.link || "none")},
        %{label: "In flight", value: format_term(bus.in_flight || "none")}
      ],
      controls: %{
        buttons: [%{id: "refresh", label: "Refresh", tone: "secondary"}],
        log_select: log_level_control(bus),
        input: %{id: "frame_timeout_ms", label: "Frame timeout (ms)", value: "25"},
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

  defp payload_dc_resource(resource, message) do
    status = dc_snapshot(resource)

    %{
      kind: "dc",
      title: "Distributed Clocks",
      status: to_string(status.lock_state),
      message: message,
      logs: payload_logs(resource),
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
        %{label: "Log level", value: Atom.to_string(current_log_level(resource))}
      ],
      controls: %{
        buttons: [%{id: "refresh", label: "Refresh", tone: "secondary"}],
        log_select: log_level_control(resource),
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

  def perform(%Master{} = resource, "activate", _params) do
    run_action(resource, fn -> EtherCAT.activate() end, "Master activated")
  end

  def perform(%Master{} = resource, "stop", _params) do
    run_action(resource, fn -> EtherCAT.stop() end, "Master stopped")
  end

  def perform(resource, "set_log_level", %{"value" => value}) do
    with {:ok, level} <- parse_log_level(value) do
      run_action(
        resource,
        fn -> WidgetLogs.set_level(resource, level) end,
        "Widget log level set to #{level}"
      )
    else
      {:error, reason} -> {:error, resource, error_message(reason)}
    end
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
        fn -> DomainAPI.update_cycle_time(id, cycle_time_us) end,
        "Domain cycle updated to #{cycle_time_us} us"
      )
    else
      {:error, reason} -> {:error, resource, error_message(reason)}
    end
  end

  def perform(%Bus{} = resource, "set_frame_timeout", %{"value" => value}) do
    with {:ok, timeout_ms} <- parse_positive_integer(value),
         bus when not is_nil(bus) <- safe(fn -> EtherCAT.bus() end, nil) do
      run_action(
        resource,
        fn -> EtherCAT.Bus.set_frame_timeout(bus, timeout_ms) end,
        "Frame timeout set to #{timeout_ms} ms"
      )
    else
      nil -> {:error, resource, error_message(:not_started)}
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

  defp fetch_bus_state do
    case safe(fn -> EtherCAT.bus() end, nil) do
      nil -> {:error, :not_started}
      {:error, _} = error -> error
      bus_server -> fetch_statem_state(bus_server)
    end
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

  defp fetch_state_name(%Bus{}) do
    case fetch_bus_state() do
      {:ok, state_name, _bus} -> state_name
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
      slaves when is_list(slaves) -> slaves
      _ -> []
    end
  end

  defp runtime_domains do
    case safe(fn -> EtherCAT.domains() end, []) do
      domains when is_list(domains) -> domains
      _ -> []
    end
  end

  defp runtime_state(default) do
    case safe(fn -> EtherCAT.state() end, default) do
      state when is_atom(state) -> state
      _ -> default
    end
  end

  defp fetch_dc_status do
    case safe(fn -> EtherCAT.dc_status() end, nil) do
      resource when is_struct(resource, EtherCAT.DC) ->
        resource

      resource when is_struct(resource, EtherCAT.DC.Status) ->
        resource

      _ ->
        default_dc_resource()
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
      summary: [],
      tables: [],
      details: [%{label: "Reason", value: format_term(reason)}],
      controls: %{
        buttons: [%{id: "refresh", label: "Refresh", tone: "secondary"}],
        log_select: log_level_control(resource)
      }
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

  defp log_level_options do
    [:debug, :info, :notice, :warning, :error, :critical, :alert, :emergency, :none, :all]
  end

  defp log_level_control(resource) do
    %{
      id: "set_log_level",
      label: "Widget log level",
      options: Enum.map(log_level_options(), &Atom.to_string/1),
      value: Atom.to_string(current_log_level(resource))
    }
  end

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

  defp queue_depths(%Bus{} = bus) do
    %{
      realtime: queue_len(bus.realtime),
      reliable: queue_len(bus.reliable)
    }
  end

  defp queue_len(queue) when is_tuple(queue) do
    :queue.len(queue)
  rescue
    _ -> 0
  end

  defp queue_len(_queue), do: 0
end
