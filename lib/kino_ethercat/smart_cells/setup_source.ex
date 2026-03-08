defmodule KinoEtherCAT.SetupSource do
  @moduledoc false

  alias KinoEtherCAT.Source

  @spec render(map()) :: String.t()
  def render(attrs) when is_map(attrs) do
    config = normalize(attrs)

    if config.interface == "" or Enum.empty?(config.slaves) do
      ""
    else
      declarative_source(config)
    end
  end

  defp declarative_source(config) do
    Source.multiline([
      aliases(config),
      "# Generated from dynamic bus discovery, but persisted as a static startup\n",
      "# configuration so the notebook can recreate the full master in one call.\n",
      "_ = EtherCAT.stop()\n\n",
      ":ok =\n",
      "  EtherCAT.start(\n",
      indent_lines(
        keyword_entries(start_entries(config) ++ [slaves: declarative_slaves(config)]),
        4
      ),
      "\n",
      "  )\n\n",
      ":ok = EtherCAT.await_running()\n",
      render_activation_wait(config)
    ])
  end

  defp aliases(config) do
    Source.multiline([
      "alias EtherCAT.Slave.Config, as: SlaveConfig\n",
      "alias EtherCAT.Domain.Config, as: DomainConfig\n",
      if(config.dc_enabled?, do: "alias EtherCAT.DC.Config, as: DCConfig\n", else: ""),
      "\n"
    ])
  end

  defp declarative_slaves(config) do
    "[" <>
      (config.slaves
       |> Enum.map(&declarative_slave_literal(&1, config))
       |> Enum.join(", ")) <> "]"
  end

  defp declarative_slave_literal(slave, config) do
    fields =
      case driver_literal(slave.driver) do
        {:ok, driver_source} ->
          [
            {"name", Source.atom_literal(slave.name)},
            {"driver", driver_source},
            {"process_data", "{:all, #{Source.atom_literal(config.domain_id)}}"},
            {"target_state", activation_target(config)}
          ]

        :error ->
          [
            {"name", Source.atom_literal(slave.name)},
            {"target_state", activation_target(config)}
          ]
      end

    "%SlaveConfig{" <>
      Enum.map_join(fields, ", ", fn {key, value} -> "#{key}: #{value}" end) <> "}"
  end

  defp render_activation_wait(%{activation_mode: :op}), do: ":ok = EtherCAT.await_operational()\n"

  defp render_activation_wait(_config), do: ""

  defp start_entries(config) do
    [
      interface: inspect(config.interface),
      backup_interface:
        if(config.backup_interface, do: inspect(config.backup_interface), else: nil),
      domains:
        "[%DomainConfig{id: #{Source.atom_literal(config.domain_id)}, cycle_time_us: #{Source.integer_literal(config.cycle_time_us)}}]",
      dc: dc_literal(config)
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp dc_literal(%{dc_enabled?: false}), do: "nil"

  defp dc_literal(config) do
    "%DCConfig{" <>
      Enum.map_join(
        [
          {"cycle_ns", Source.integer_literal(config.cycle_time_us * 1_000)},
          {"await_lock?", if(config.await_lock?, do: "true", else: "false")},
          {"lock_threshold_ns", Source.integer_literal(config.lock_threshold_ns)},
          {"lock_timeout_ms", Source.integer_literal(config.lock_timeout_ms)}
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
    %{
      interface: attrs |> Map.get("interface", "") |> String.trim(),
      backup_interface: attrs |> Map.get("backup_interface", "") |> blank_to_nil(),
      domain_id: attrs |> Map.get("domain_id", "main") |> String.trim(),
      cycle_time_us: attrs |> Map.get("cycle_time_us", 1_000) |> positive_integer(1_000),
      activation_mode: attrs |> Map.get("activation_mode", "op") |> activation_mode(),
      dc_enabled?: attrs |> Map.get("dc_enabled?", true) |> truthy?(),
      await_lock?: attrs |> Map.get("await_lock?", false) |> truthy?(),
      lock_threshold_ns: attrs |> Map.get("lock_threshold_ns", 100) |> positive_integer(100),
      lock_timeout_ms: attrs |> Map.get("lock_timeout_ms", 5_000) |> positive_integer(5_000),
      slaves: normalize_slaves(attrs["slaves"] || [])
    }
  end

  defp normalize_slaves(slaves) do
    Enum.map(slaves, fn slave ->
      %{
        name: slave |> Map.get("name", "") |> String.trim(),
        discovered_name: slave |> Map.get("discovered_name", "") |> String.trim(),
        driver: slave |> Map.get("driver", "") |> String.trim()
      }
    end)
  end

  defp activation_mode("preop"), do: :preop
  defp activation_mode(_mode), do: :op

  defp activation_target(%{activation_mode: :preop}), do: ":preop"
  defp activation_target(_config), do: ":op"

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

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(_value), do: nil

  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?(_value), do: false

  defp indent_lines(content, spaces) do
    padding = String.duplicate(" ", spaces)

    content
    |> String.split("\n")
    |> Enum.map_join("\n", &(padding <> &1))
  end
end
