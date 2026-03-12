defmodule KinoEtherCAT.SmartCells.SetupSource do
  @moduledoc false

  alias KinoEtherCAT.SmartCells.{SetupTransport, Source}

  @udp_start_retry_attempts 3
  @udp_start_retry_delay_ms 20

  @spec render(map()) :: String.t()
  def render(attrs) when is_map(attrs) do
    config = normalize(attrs)

    with false <- Enum.empty?(config.slaves),
         {:ok, transport} <- SetupTransport.source_config(config) do
      config
      |> static_start_source(transport)
      |> Source.format()
    else
      _ -> ""
    end
  end

  defp static_start_source(config, transport) do
    Source.multiline([
      aliases(config),
      transport_prelude(transport),
      "# Persisted from live bus discovery.\n",
      "# The notebook now boots the master from a single static EtherCAT.start/1 call.\n",
      "_ = EtherCAT.stop()\n\n",
      start_prelude(config, transport),
      "setup_result =\n",
      "  with :ok <- ",
      start_call(transport),
      ",\n",
      "       :ok <- EtherCAT.await_running(),\n",
      "       :ok <- EtherCAT.await_operational() do\n",
      "    :ok\n",
      "  end\n\n",
      "case setup_result do\n",
      "  :ok ->\n",
      "    Kino.Layout.tabs(\n",
      "      Master: KinoEtherCAT.master(),\n",
      "      \"Task Manager\": KinoEtherCAT.diagnostics()\n",
      "    )\n\n",
      "  {:error, reason} ->\n",
      "    _ = EtherCAT.stop()\n\n",
      "    Kino.Markdown.new(\"\"\"\n",
      "    ## EtherCAT setup failed\n\n",
      "    `\#{inspect(reason)}`\n\n",
      "    The generated setup cell kept the notebook running instead of crashing.\n",
      "    Re-run the cell once the bus is stable. Configuration timeouts usually mean one or more slaves did not reach the requested state in time.\n",
      "    \"\"\")\n",
      "end\n"
    ])
  end

  defp start_prelude(config, %{transport: :udp} = transport) do
    Source.multiline([
      "start_master = fn start_master, attempts_left ->\n",
      "  result =\n",
      "    EtherCAT.start(\n",
      indent_lines(
        keyword_entries(
          start_entries(config, transport) ++ [slaves: slave_literals(config.slaves)]
        ),
        6
      ),
      "\n",
      "    )\n\n",
      "  case result do\n",
      "    {:error, :eaddrinuse} when attempts_left > 1 ->\n",
      "      Process.sleep(#{@udp_start_retry_delay_ms})\n",
      "      start_master.(start_master, attempts_left - 1)\n\n",
      "    {:error, {:open_failed, :eaddrinuse}} when attempts_left > 1 ->\n",
      "      Process.sleep(#{@udp_start_retry_delay_ms})\n",
      "      start_master.(start_master, attempts_left - 1)\n\n",
      "    other ->\n",
      "      other\n",
      "  end\n",
      "end\n\n"
    ])
  end

  defp start_prelude(config, transport) do
    Source.multiline([
      "start_master = fn ->\n",
      "  EtherCAT.start(\n",
      indent_lines(
        keyword_entries(
          start_entries(config, transport) ++ [slaves: slave_literals(config.slaves)]
        ),
        4
      ),
      "\n",
      "  )\n",
      "end\n\n"
    ])
  end

  defp start_call(%{transport: :udp}),
    do: "start_master.(start_master, #{@udp_start_retry_attempts})"

  defp start_call(_transport), do: "start_master.()"

  defp aliases(config) do
    Source.multiline([
      "alias EtherCAT.Slave.Config, as: SlaveConfig\n",
      "alias EtherCAT.Domain.Config, as: DomainConfig\n",
      if(config.dc_enabled, do: "alias EtherCAT.DC.Config, as: DCConfig\n", else: ""),
      "\n"
    ])
  end

  defp transport_prelude(%{transport: :raw}), do: ""

  defp transport_prelude(%{transport: :udp, host: host, bind_ip: bind_ip}) do
    Source.multiline([
      "udp_host = ",
      ip_literal(host),
      "\n",
      if(bind_ip, do: ["udp_bind_ip = ", ip_literal(bind_ip), "\n"], else: ""),
      "\n"
    ])
  end

  defp slave_literals(slaves) do
    "[" <>
      (slaves
       |> Enum.map(&slave_literal/1)
       |> Enum.join(", ")) <> "]"
  end

  defp start_entries(config, transport) do
    (transport_entries(transport) ++
       startup_tuning_entries(transport) ++
       [
         domains: domain_literals(config.domains),
         dc: dc_literal(config)
       ])
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp transport_entries(%{transport: :raw, interface: interface}) do
    [interface: inspect(interface)]
  end

  defp transport_entries(%{transport: :udp, port: port, bind_ip: bind_ip}) do
    [transport: ":udp", host: "udp_host", port: Source.integer_literal(port)] ++
      if(bind_ip, do: [bind_ip: "udp_bind_ip"], else: [])
  end

  defp startup_tuning_entries(%{transport: :udp}) do
    # Livebook + simulator UDP is more scheduler-sensitive than raw-socket hardware,
    # so keep the bus response timeout above the master's 2ms auto floor.
    [frame_timeout_ms: "10"]
  end

  defp startup_tuning_entries(_transport), do: []

  defp domain_literals(domains) do
    "[" <>
      Enum.map_join(domains, ", ", fn domain ->
        "%DomainConfig{" <>
          Enum.map_join(
            [
              {"id", Source.atom_literal(domain.id)},
              {"cycle_time_us", Source.integer_literal(domain.cycle_time_us)},
              {"miss_threshold", Source.integer_literal(domain.miss_threshold)}
            ],
            ", ",
            fn {key, value} -> "#{key}: #{value}" end
          ) <> "}"
      end) <> "]"
  end

  defp dc_literal(%{dc_enabled: false}), do: "nil"

  defp dc_literal(config) do
    "%DCConfig{" <>
      Enum.map_join(
        [
          {"cycle_ns", Source.integer_literal(config.dc_cycle_ns)},
          {"await_lock?", if(config.await_lock, do: "true", else: "false")},
          {"lock_threshold_ns", Source.integer_literal(config.lock_threshold_ns)},
          {"lock_timeout_ms", Source.integer_literal(config.lock_timeout_ms)},
          {"warmup_cycles", Source.integer_literal(config.warmup_cycles)}
        ],
        ", ",
        fn {key, value} -> "#{key}: #{value}" end
      ) <> "}"
  end

  defp keyword_entries(entries) do
    entries
    |> Enum.map_join(",\n", fn {key, value} -> "#{key}: #{value}" end)
  end

  defp normalize(attrs) do
    transport = SetupTransport.normalize(attrs)
    domains = attrs |> Map.get("domains", legacy_domains(attrs)) |> normalize_domains()

    %{
      transport: transport.transport,
      interface: transport.interface,
      host: transport.host,
      port: transport.port,
      domains: domains,
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
      warmup_cycles: attrs |> Map.get("warmup_cycles", 0) |> non_negative_integer(0),
      slaves: normalize_slaves(attrs["slaves"] || [], domains)
    }
  end

  defp normalize_domains(domains) when is_list(domains) do
    normalized =
      domains
      |> Enum.map(&normalize_domain/1)
      |> Enum.reject(&(&1.id == ""))
      |> Enum.uniq_by(& &1.id)

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
      id: domain |> Map.get("id", "main") |> String.trim(),
      cycle_time_ms: cycle_time_ms,
      cycle_time_us: cycle_time_ms * 1_000,
      miss_threshold: domain |> Map.get("miss_threshold", 1_000) |> positive_integer(1_000)
    }
  end

  defp normalize_domain(_domain), do: default_domain()

  defp normalize_slaves(slaves, domains) do
    default_domain_id = domains |> List.first() |> Map.get(:id)

    Enum.map(slaves, fn slave ->
      %{
        name: slave |> Map.get("name", "") |> String.trim(),
        discovered_name: slave |> Map.get("discovered_name", "") |> String.trim(),
        driver: slave |> Map.get("driver", "") |> String.trim(),
        domain_id:
          normalize_domain_id(
            Map.get(slave, "domain_id"),
            Map.get(slave, "driver", ""),
            domains,
            default_domain_id
          )
      }
    end)
  end

  defp slave_literal(slave) do
    base_fields = [{"name", Source.atom_literal(slave.name)}]

    fields =
      case driver_literal(slave.driver) do
        {:ok, driver_source} ->
          base_fields ++
            [
              {"driver", driver_source},
              {"process_data", process_data_literal(slave.domain_id)},
              {"target_state", ":op"}
            ]

        :error ->
          base_fields ++ [{"target_state", ":op"}]
      end

    "%SlaveConfig{" <>
      Enum.map_join(fields, ", ", fn {key, value} -> "#{key}: #{value}" end) <> "}"
  end

  defp process_data_literal(""), do: ":none"
  defp process_data_literal(domain_id), do: "{:all, #{Source.atom_literal(domain_id)}}"

  defp driver_literal(driver) when is_binary(driver) do
    Source.module_literal(driver)
  end

  defp driver_literal(_driver), do: :error

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

  defp normalize_domain_id(value, driver, domains, default_domain_id) do
    valid_ids = Enum.map(domains, & &1.id)
    driver = String.trim(to_string(driver))
    value = String.trim(to_string(value || ""))

    cond do
      driver == "" -> ""
      value in valid_ids -> value
      default_domain_id in valid_ids -> default_domain_id
      true -> ""
    end
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
    %{id: "main", cycle_time_ms: 10, cycle_time_us: 10_000, miss_threshold: 1_000}
  end

  defp default_dc_cycle_ns([domain | _rest]), do: domain.cycle_time_ms * 1_000_000
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

  defp indent_lines(content, spaces) do
    padding = String.duplicate(" ", spaces)

    content
    |> String.split("\n")
    |> Enum.map_join("\n", &(padding <> &1))
  end

  defp ip_literal({a, b, c, d}), do: "{#{a}, #{b}, #{c}, #{d}}"
end
