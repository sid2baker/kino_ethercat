defmodule KinoEtherCAT.SmartCells.ExplorerSource do
  @moduledoc false

  alias KinoEtherCAT.SmartCells.Source

  @spec render_capture(map()) :: String.t()
  def render_capture(attrs) when is_map(attrs) do
    with {:ok, capture} <- capture_snapshot_from_attrs(attrs),
         {:ok, driver_name} <- capture_driver_name(attrs["driver_name"], attrs["slave"]),
         {:ok, driver_module} <- capture_driver_module_literal(driver_name),
         {:ok, simulator_module} <- capture_simulator_module_literal(driver_name),
         {:ok, signal_names} <- capture_signal_name_overrides(attrs),
         {:ok, source} <-
           EtherCAT.Capture.render_driver(
             capture,
             Keyword.merge(
               capture_sdo_opts(Map.get(attrs, "capture_sdos", "")),
               module: driver_module,
               simulator_module: simulator_module,
               signal_names: signal_names
             )
           ) do
      source
    else
      :error -> ""
      {:error, _reason} -> ""
    end
  end

  @spec render_sdo(map()) :: String.t()
  def render_sdo(attrs) when is_map(attrs) do
    with {:ok, slave} <- slave_literal(attrs["slave"]),
         {:ok, index} <- integer_literal(attrs["index"]),
         {:ok, subindex} <- integer_literal(attrs["subindex"]) do
      source =
        case Map.get(attrs, "operation", "upload") do
          "download" ->
            with {:ok, payload} <- binary_literal(attrs["write_data"]) do
              Source.multiline([
                "payload = #{payload}\n\n",
                "case EtherCAT.download_sdo(#{slave}, #{index}, #{subindex}, payload) do\n",
                "  :ok ->\n",
                "    %{\n",
                "      operation: :download,\n",
                "      slave: #{slave},\n",
                "      index: #{index},\n",
                "      subindex: #{subindex},\n",
                "      bytes: byte_size(payload),\n",
                "      hex: Base.encode16(payload, case: :upper),\n",
                "      result: :ok\n",
                "    }\n\n",
                "  {:error, reason} -> {:error, reason}\n",
                "end\n"
              ])
            else
              :error -> ""
            end

          _ ->
            Source.multiline([
              "case EtherCAT.upload_sdo(#{slave}, #{index}, #{subindex}) do\n",
              "  {:ok, binary} ->\n",
              "    %{\n",
              "      operation: :upload,\n",
              "      slave: #{slave},\n",
              "      index: #{index},\n",
              "      subindex: #{subindex},\n",
              "      bytes: byte_size(binary),\n",
              "      hex: Base.encode16(binary, case: :upper),\n",
              "      binary: binary\n",
              "    }\n\n",
              "  {:error, reason} -> {:error, reason}\n",
              "end\n"
            ])
        end

      Source.format(source)
    else
      :error -> ""
    end
  end

  @spec render_register(map()) :: String.t()
  def render_register(attrs) when is_map(attrs) do
    with {:ok, slave} <- slave_literal(attrs["slave"]),
         {:ok, spec} <- register_spec(attrs) do
      aliases = "alias EtherCAT.Bus.Transaction\nalias EtherCAT.Slave.ESC.Registers\n\n"

      source =
        case Map.get(attrs, "operation", "read") do
          "write" ->
            Source.multiline([
              aliases,
              "register = #{spec.source}\n\n",
              "with {:ok, bus} when not is_nil(bus) <- EtherCAT.bus(),\n",
              "     {:ok, %{station: station}} <- EtherCAT.slave_info(#{slave}),\n",
              "     {:ok, [%{wkc: wkc}]} <-\n",
              "       EtherCAT.Bus.transaction(bus, Transaction.fpwr(station, register)) do\n",
              "  %{\n",
              "    operation: :write,\n",
              "    slave: #{slave},\n",
              "    station: station,\n",
              "    register: #{spec.label},\n",
              "    address: elem(register, 0),\n",
              "    bytes: byte_size(elem(register, 1)),\n",
              "    hex: Base.encode16(elem(register, 1), case: :upper),\n",
              "    wkc: wkc\n",
              "  }\n",
              "end\n"
            ])

          _ ->
            decoded_line =
              case spec.decoder do
                nil -> "    decoded: nil,\n"
                decoder -> "    decoded: #{decoder},\n"
              end

            Source.multiline([
              aliases,
              "register = #{spec.source}\n\n",
              "with {:ok, bus} when not is_nil(bus) <- EtherCAT.bus(),\n",
              "     {:ok, %{station: station}} <- EtherCAT.slave_info(#{slave}),\n",
              "     {:ok, [%{data: data, wkc: wkc}]} <-\n",
              "       EtherCAT.Bus.transaction(bus, Transaction.fprd(station, register)) do\n",
              "  %{\n",
              "    operation: :read,\n",
              "    slave: #{slave},\n",
              "    station: station,\n",
              "    register: #{spec.label},\n",
              "    address: elem(register, 0),\n",
              "    bytes: byte_size(data),\n",
              "    hex: Base.encode16(data, case: :upper),\n",
              decoded_line,
              "    wkc: wkc,\n",
              "    binary: data\n",
              "  }\n",
              "end\n"
            ])
        end

      Source.format(source)
    else
      :error -> ""
    end
  end

  @spec render_sii(map()) :: String.t()
  def render_sii(attrs) when is_map(attrs) do
    with {:ok, slave} <- slave_literal(attrs["slave"]),
         {:ok, action} <- sii_action(Map.get(attrs, "operation", "identity")) do
      aliases = "alias EtherCAT.Slave.ESC.SII\n\n"

      source =
        case action do
          :identity ->
            simple_sii_call(
              aliases,
              slave,
              "SII.read_identity(bus, station)",
              "identity"
            )

          :mailbox ->
            simple_sii_call(
              aliases,
              slave,
              "SII.read_mailbox_config(bus, station)",
              "mailbox"
            )

          :sync_managers ->
            simple_sii_call(
              aliases,
              slave,
              "SII.read_sm_configs(bus, station)",
              "sync_managers"
            )

          :pdo_configs ->
            simple_sii_call(
              aliases,
              slave,
              "SII.read_pdo_configs(bus, station)",
              "pdo_configs"
            )

          :reload ->
            Source.multiline([
              aliases,
              "with {:ok, bus} when not is_nil(bus) <- EtherCAT.bus(),\n",
              "     {:ok, %{station: station}} <- EtherCAT.slave_info(#{slave}),\n",
              "     :ok <- SII.reload(bus, station) do\n",
              "  %{operation: :reload, slave: #{slave}, station: station, result: :ok}\n",
              "end\n"
            ])

          :dump ->
            Source.multiline([
              aliases,
              "with {:ok, bus} when not is_nil(bus) <- EtherCAT.bus(),\n",
              "     {:ok, %{station: station}} <- EtherCAT.slave_info(#{slave}),\n",
              "     {:ok, binary} <- SII.dump(bus, station) do\n",
              "  %{\n",
              "    operation: :dump,\n",
              "    slave: #{slave},\n",
              "    station: station,\n",
              "    bytes: byte_size(binary),\n",
              "    preview_hex: Base.encode16(binary_part(binary, 0, min(byte_size(binary), 64)), case: :upper),\n",
              "    binary: binary\n",
              "  }\n",
              "end\n"
            ])

          :read_words ->
            with {:ok, word_address} <- integer_literal(attrs["word_address"]),
                 {:ok, word_count} <- integer_literal(attrs["word_count"]) do
              Source.multiline([
                aliases,
                "with {:ok, bus} when not is_nil(bus) <- EtherCAT.bus(),\n",
                "     {:ok, %{station: station}} <- EtherCAT.slave_info(#{slave}),\n",
                "     {:ok, binary} <- SII.read(bus, station, #{word_address}, #{word_count}) do\n",
                "  %{\n",
                "    operation: :read_words,\n",
                "    slave: #{slave},\n",
                "    station: station,\n",
                "    word_address: #{word_address},\n",
                "    word_count: #{word_count},\n",
                "    bytes: byte_size(binary),\n",
                "    hex: Base.encode16(binary, case: :upper),\n",
                "    binary: binary\n",
                "  }\n",
                "end\n"
              ])
            else
              :error -> ""
            end

          :write_words ->
            with {:ok, word_address} <- integer_literal(attrs["word_address"]),
                 {:ok, payload} <- binary_literal(attrs["write_data"]) do
              Source.multiline([
                aliases,
                "payload = #{payload}\n\n",
                "with {:ok, bus} when not is_nil(bus) <- EtherCAT.bus(),\n",
                "     {:ok, %{station: station}} <- EtherCAT.slave_info(#{slave}),\n",
                "     :ok <- SII.write(bus, station, #{word_address}, payload) do\n",
                "  %{\n",
                "    operation: :write_words,\n",
                "    slave: #{slave},\n",
                "    station: station,\n",
                "    word_address: #{word_address},\n",
                "    bytes: byte_size(payload),\n",
                "    hex: Base.encode16(payload, case: :upper),\n",
                "    result: :ok\n",
                "  }\n",
                "end\n"
              ])
            else
              :error -> ""
            end
        end

      Source.format(source)
    else
      :error -> ""
    end
  end

  defp register_spec(%{"operation" => "write"} = attrs) do
    case Map.get(attrs, "register_mode", "preset") do
      "raw" -> raw_write_spec(attrs)
      _ -> preset_write_spec(attrs)
    end
  end

  defp register_spec(attrs) do
    case Map.get(attrs, "register_mode", "preset") do
      "raw" -> raw_read_spec(attrs)
      _ -> preset_read_spec(attrs)
    end
  end

  defp preset_read_spec(attrs) do
    channel = Map.get(attrs, "channel")

    case Map.get(attrs, "register", "al_status") do
      "al_status" ->
        {:ok,
         %{
           source: "Registers.al_status()",
           label: ":al_status",
           decoder: "Registers.decode_al_status(data)"
         }}

      "al_status_code" ->
        {:ok, %{source: "Registers.al_status_code()", label: ":al_status_code", decoder: nil}}

      "dl_status" ->
        {:ok, %{source: "Registers.dl_status()", label: ":dl_status", decoder: nil}}

      "rx_error_counter" ->
        {:ok,
         %{
           source: "Registers.rx_error_counter()",
           label: ":rx_error_counter",
           decoder: "Registers.decode_rx_errors(data)"
         }}

      "lost_link_counter" ->
        {:ok,
         %{source: "Registers.lost_link_counter()", label: ":lost_link_counter", decoder: nil}}

      "wdt_status" ->
        {:ok,
         %{
           source: "Registers.wdt_status()",
           label: ":wdt_status",
           decoder: "Registers.wdt_status_expired?(data)"
         }}

      "sm_status" ->
        with {:ok, idx} <- integer_literal(channel),
             do:
               {:ok, %{source: "Registers.sm_status(#{idx})", label: ":sm_status", decoder: nil}},
             else: (_ -> :error)

      "sm_activate" ->
        with {:ok, idx} <- integer_literal(channel),
             do:
               {:ok,
                %{source: "Registers.sm_activate(#{idx})", label: ":sm_activate", decoder: nil}},
             else: (_ -> :error)

      _ ->
        :error
    end
  end

  defp raw_read_spec(attrs) do
    with {:ok, address} <- integer_literal(attrs["address"]),
         {:ok, size} <- integer_literal(attrs["size"]) do
      {:ok, %{source: "{#{address}, #{size}}", label: ":raw", decoder: nil}}
    else
      :error -> :error
    end
  end

  defp preset_write_spec(attrs) do
    value = Map.get(attrs, "value")
    channel = Map.get(attrs, "channel")

    case Map.get(attrs, "register", "al_control") do
      "al_control" ->
        with {:ok, encoded} <- integer_literal(value),
             do: {:ok, %{source: "Registers.al_control(#{encoded})", label: ":al_control"}},
             else: (_ -> :error)

      "dl_port_control" ->
        with {:ok, encoded} <- integer_literal(value),
             do:
               {:ok,
                %{source: "Registers.dl_port_control(#{encoded})", label: ":dl_port_control"}},
             else: (_ -> :error)

      "dl_alias_control" ->
        with {:ok, encoded} <- integer_literal(value),
             do:
               {:ok,
                %{source: "Registers.dl_alias_control(#{encoded})", label: ":dl_alias_control"}},
             else: (_ -> :error)

      "ecat_event_mask" ->
        with {:ok, encoded} <- integer_literal(value),
             do:
               {:ok,
                %{source: "Registers.ecat_event_mask(#{encoded})", label: ":ecat_event_mask"}},
             else: (_ -> :error)

      "sm_activate" ->
        with {:ok, idx} <- integer_literal(channel),
             {:ok, enabled} <- integer_literal(value) do
          {:ok, %{source: "Registers.sm_activate(#{idx}, #{enabled})", label: ":sm_activate"}}
        else
          :error -> :error
        end

      _ ->
        :error
    end
  end

  defp raw_write_spec(attrs) do
    with {:ok, address} <- integer_literal(attrs["address"]),
         {:ok, payload} <- binary_literal(attrs["write_data"]) do
      {:ok, %{source: "{#{address}, #{payload}}", label: ":raw"}}
    else
      :error -> :error
    end
  end

  defp simple_sii_call(aliases, slave, call_source, operation_name) do
    Source.multiline([
      aliases,
      "with {:ok, bus} when not is_nil(bus) <- EtherCAT.bus(),\n",
      "     {:ok, %{station: station}} <- EtherCAT.slave_info(#{slave}),\n",
      "     {:ok, result} <- #{call_source} do\n",
      "  %{operation: :#{operation_name}, slave: #{slave}, station: station, result: result}\n",
      "end\n"
    ])
  end

  defp sii_action("identity"), do: {:ok, :identity}
  defp sii_action("mailbox"), do: {:ok, :mailbox}
  defp sii_action("sync_managers"), do: {:ok, :sync_managers}
  defp sii_action("pdo_configs"), do: {:ok, :pdo_configs}
  defp sii_action("read_words"), do: {:ok, :read_words}
  defp sii_action("write_words"), do: {:ok, :write_words}
  defp sii_action("dump"), do: {:ok, :dump}
  defp sii_action("reload"), do: {:ok, :reload}
  defp sii_action(_value), do: :error

  defp slave_literal(value) when is_binary(value) do
    case String.trim(value) do
      "" -> :error
      trimmed -> {:ok, Source.atom_literal(trimmed)}
    end
  end

  defp slave_literal(_value), do: :error

  defp capture_snapshot_from_attrs(attrs) when is_map(attrs) do
    case Map.get(attrs, "capture_snapshot") do
      value when is_binary(value) and value != "" ->
        with {:ok, binary} <- Base.decode64(value, padding: false) do
          {:ok, :erlang.binary_to_term(binary)}
        else
          :error -> {:error, :invalid_capture_snapshot}
        end

      _ ->
        {:error, :missing_capture_snapshot}
    end
  rescue
    _ -> {:error, :invalid_capture_snapshot}
  end

  defp integer_literal(value) when is_integer(value) and value >= 0 do
    {:ok, Integer.to_string(value)}
  end

  defp integer_literal(value) when is_binary(value) do
    trimmed = String.trim(value)

    cond do
      trimmed == "" ->
        :error

      String.starts_with?(String.downcase(trimmed), "0x") ->
        case Integer.parse(String.slice(trimmed, 2..-1//1), 16) do
          {integer, ""} when integer >= 0 ->
            {:ok, "0x" <> String.upcase(Integer.to_string(integer, 16))}

          _ ->
            :error
        end

      true ->
        case Integer.parse(trimmed) do
          {integer, ""} when integer >= 0 -> {:ok, Integer.to_string(integer)}
          _ -> :error
        end
    end
  end

  defp integer_literal(_value), do: :error

  defp binary_literal(value) when is_binary(value) do
    digits =
      value
      |> String.replace(~r/[^0-9A-Fa-f]/u, "")
      |> String.upcase()

    cond do
      digits == "" ->
        :error

      rem(byte_size(digits), 2) != 0 ->
        :error

      true ->
        bytes =
          digits
          |> String.codepoints()
          |> Enum.chunk_every(2)
          |> Enum.map_join(", ", fn [high, low] -> "0x#{high}#{low}" end)

        {:ok, "<<#{bytes}>>"}
    end
  end

  defp binary_literal(_value), do: :error

  defp capture_driver_module_literal(driver_name) when is_binary(driver_name) do
    driver_name
    |> capture_driver_module()
    |> Source.module_literal()
  end

  defp capture_simulator_module_literal(driver_name) when is_binary(driver_name) do
    driver_name
    |> capture_simulator_module()
    |> Source.module_literal()
  end

  defp capture_driver_name(value, slave_name) when is_binary(value) do
    case normalize_capture_driver_name(value) do
      "" -> {:ok, default_capture_driver_name(slave_name)}
      normalized -> {:ok, normalized}
    end
  end

  defp capture_driver_name(_value, slave_name), do: {:ok, default_capture_driver_name(slave_name)}

  defp default_capture_driver_name(slave_name) do
    normalize_capture_driver_name(to_string(slave_name || "Device"))
    |> case do
      "" -> "Device"
      normalized -> normalized
    end
  end

  defp capture_driver_module(driver_name) when is_binary(driver_name) do
    "EtherCAT.Drivers." <> driver_name
  end

  defp capture_simulator_module(driver_name) when is_binary(driver_name) do
    capture_driver_module(driver_name) <> ".Simulator"
  end

  defp normalize_capture_driver_name(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.trim_leading("Elixir.")
    |> String.replace_prefix("EtherCAT.Drivers.", "")
    |> String.replace_suffix(".Simulator", "")
    |> String.split(".", trim: true)
    |> Enum.map(&normalize_capture_driver_name_segment/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(".")
  end

  defp normalize_capture_driver_name(_value), do: ""

  defp normalize_capture_driver_name_segment(segment) do
    trimmed = String.trim(segment)

    cond do
      trimmed == "" ->
        ""

      String.match?(trimmed, ~r/^[A-Z][A-Za-z0-9_]*$/) ->
        trimmed

      true ->
        trimmed
        |> Macro.camelize()
        |> ensure_driver_name_segment()
    end
  end

  defp ensure_driver_name_segment(""), do: ""

  defp ensure_driver_name_segment(segment) do
    if String.match?(segment, ~r/^[A-Z][A-Za-z0-9_]*$/) do
      segment
    else
      "Device" <> segment
    end
  end

  defp capture_signal_entries_from_attrs(attrs) when is_map(attrs) do
    attrs
    |> Map.get("capture_signal_entries", [])
    |> Enum.flat_map(fn
      %{
        "key" => key,
        "name" => name,
        "direction" => direction,
        "pdo_index" => pdo_index,
        "bit_size" => bit_size
      } ->
        [
          %{
            key: to_string(key),
            name: normalize_capture_name(name),
            direction: normalize_capture_direction(direction),
            pdo_index: pdo_index,
            bit_size: bit_size
          }
        ]

      %{
        key: key,
        name: name,
        direction: direction,
        pdo_index: pdo_index,
        bit_size: bit_size
      } ->
        [
          %{
            key: to_string(key),
            name: normalize_capture_name(name),
            direction: normalize_capture_direction(direction),
            pdo_index: pdo_index,
            bit_size: bit_size
          }
        ]

      _ ->
        []
    end)
    |> Enum.reject(&(is_nil(&1.direction) or is_nil(&1.pdo_index) or is_nil(&1.bit_size)))
  end

  defp capture_signal_name_overrides(attrs) when is_map(attrs) do
    attrs
    |> capture_signal_entries_from_attrs()
    |> Enum.reduce({:ok, %{}}, fn entry, {:ok, acc} ->
      {:ok, Map.put(acc, {entry.direction, entry.pdo_index}, entry.name)}
    end)
  end

  defp normalize_capture_name(name) when is_binary(name) do
    case String.trim(name) do
      "" -> "signal"
      trimmed -> trimmed
    end
  end

  defp normalize_capture_name(name), do: to_string(name)

  defp normalize_capture_direction(direction) when direction in [:input, :output], do: direction
  defp normalize_capture_direction("input"), do: :input
  defp normalize_capture_direction("output"), do: :output
  defp normalize_capture_direction(_direction), do: nil

  defp capture_sdo_opts(value) do
    case parse_capture_sdos(value) do
      [] -> []
      refs -> [sdos: refs]
    end
  end

  defp parse_capture_sdos(value) when is_binary(value) do
    value
    |> String.split(~r/[\n,;]+/, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.reduce([], fn line, acc ->
      case parse_capture_sdo(line) do
        {:ok, ref} -> acc ++ [ref]
        :error -> acc
      end
    end)
  end

  defp parse_capture_sdos(_value), do: []

  defp parse_capture_sdo(line) do
    case Regex.run(~r/^(.+?)(?::|\s+)(.+)$/, line, capture: :all_but_first) do
      [index, subindex] ->
        with {:ok, index} <- integer_value(index),
             {:ok, subindex} <- integer_value(subindex) do
          {:ok, {index, subindex}}
        end

      _ ->
        :error
    end
  end

  defp integer_value(value) when is_binary(value) do
    trimmed = String.trim(value)

    cond do
      trimmed == "" ->
        :error

      String.starts_with?(String.downcase(trimmed), "0x") ->
        case Integer.parse(String.slice(trimmed, 2..-1//1), 16) do
          {integer, ""} when integer >= 0 -> {:ok, integer}
          _ -> :error
        end

      true ->
        case Integer.parse(trimmed) do
          {integer, ""} when integer >= 0 -> {:ok, integer}
          _ -> :error
        end
    end
  end

  defp integer_value(_value), do: :error
end
