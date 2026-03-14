defmodule KinoEtherCAT.SmartCells.ExplorerRuntime do
  @moduledoc false

  alias EtherCAT.Bus.Transaction
  alias EtherCAT.Slave.ESC.{Registers, SII}

  @sii_operations ~w(identity mailbox sync_managers pdo_configs read_words write_words dump reload)

  @spec run_register(map()) :: {:ok, [map()]} | {:error, term()}
  def run_register(attrs) when is_map(attrs) do
    with {:ok, slave} <- slave_atom(Map.get(attrs, "slave")),
         {:ok, spec} <- register_spec(attrs),
         {:ok, bus} when not is_nil(bus) <- EtherCAT.bus(),
         {:ok, %{station: station}} <- EtherCAT.slave_info(slave) do
      case Map.get(attrs, "operation", "read") do
        "write" ->
          with {:ok, [%{wkc: wkc}]} <-
                 EtherCAT.Bus.transaction(bus, Transaction.fpwr(station, spec.register)) do
            {:ok,
             [
               properties_section("Register Write", [
                 {"Slave", inspect(slave)},
                 {"Station", hex(station, 4)},
                 {"Register", spec.label},
                 {"Bytes", Integer.to_string(byte_size(elem(spec.register, 1)))},
                 {"WKC", Integer.to_string(wkc)}
               ])
             ]}
          end

        _ ->
          with {:ok, [%{data: data, wkc: wkc}]} <-
                 EtherCAT.Bus.transaction(bus, Transaction.fprd(station, spec.register)) do
            {:ok,
             [
               properties_section("Register Read", [
                 {"Slave", inspect(slave)},
                 {"Station", hex(station, 4)},
                 {"Register", spec.label},
                 {"Bytes", Integer.to_string(byte_size(data))},
                 {"Hex", Base.encode16(data, case: :upper)},
                 {"Decoded", decode_value(spec.decoder, data)},
                 {"WKC", Integer.to_string(wkc)}
               ])
             ]}
          end
      end
    end
  end

  @spec run_sdo(map()) :: {:ok, [map()]} | {:error, term()}
  def run_sdo(attrs) when is_map(attrs) do
    with {:ok, slave} <- slave_atom(Map.get(attrs, "slave")),
         {:ok, index} <- integer_value(Map.get(attrs, "sdo_index")),
         {:ok, subindex} <- integer_value(Map.get(attrs, "sdo_subindex")) do
      case Map.get(attrs, "sdo_operation", "upload") do
        "download" ->
          with {:ok, payload} <- binary_value(Map.get(attrs, "sdo_write_data")),
               :ok <- EtherCAT.download_sdo(slave, index, subindex, payload) do
            {:ok,
             [
               properties_section("CoE Download", [
                 {"Slave", inspect(slave)},
                 {"Index", hex(index, 4)},
                 {"Subindex", hex(subindex, 2)},
                 {"Bytes", Integer.to_string(byte_size(payload))},
                 {"Hex", Base.encode16(payload, case: :upper)},
                 {"Result", "ok"}
               ])
             ]}
          end

        _ ->
          with {:ok, binary} <- EtherCAT.upload_sdo(slave, index, subindex) do
            {:ok,
             [
               properties_section("CoE Upload", [
                 {"Slave", inspect(slave)},
                 {"Index", hex(index, 4)},
                 {"Subindex", hex(subindex, 2)},
                 {"Bytes", Integer.to_string(byte_size(binary))},
                 {"Hex", Base.encode16(binary, case: :upper)}
               ])
             ]}
          end
      end
    end
  end

  @spec run_sii(map()) :: {:ok, [map()]} | {:error, term()}
  def run_sii(attrs) when is_map(attrs) do
    with {:ok, slave} <- slave_atom(Map.get(attrs, "slave")),
         {:ok, bus} when not is_nil(bus) <- EtherCAT.bus(),
         {:ok, %{station: station}} <- EtherCAT.slave_info(slave),
         {:ok, action} <- sii_action(Map.get(attrs, "sii_operation", "identity")) do
      run_sii_action(action, attrs, slave, bus, station)
    end
  end

  defp run_sii_action(:identity, _attrs, slave, bus, station) do
    with {:ok, identity} <- SII.read_identity(bus, station) do
      {:ok,
       [
         properties_section("SII Identity", [
           {"Slave", inspect(slave)},
           {"Station", hex(station, 4)},
           {"Vendor", hex(Map.get(identity, :vendor_id, 0), 8)},
           {"Product", hex(Map.get(identity, :product_code, 0), 8)},
           {"Revision", hex(Map.get(identity, :revision, 0), 8)},
           {"Serial", hex(Map.get(identity, :serial_number, 0), 8)}
         ])
       ]}
    end
  end

  defp run_sii_action(:mailbox, _attrs, slave, bus, station) do
    with {:ok, mailbox} <- SII.read_mailbox_config(bus, station) do
      {:ok,
       [
         properties_section("SII Mailbox", [
           {"Slave", inspect(slave)},
           {"Receive offset", hex(Map.get(mailbox, :recv_offset, 0), 4)},
           {"Receive size", Integer.to_string(Map.get(mailbox, :recv_size, 0))},
           {"Send offset", hex(Map.get(mailbox, :send_offset, 0), 4)},
           {"Send size", Integer.to_string(Map.get(mailbox, :send_size, 0))}
         ])
       ]}
    end
  end

  defp run_sii_action(:sync_managers, _attrs, slave, bus, station) do
    with {:ok, sm_configs} <- SII.read_sm_configs(bus, station) do
      {:ok,
       [
         table_section(
           "SII Sync Managers",
           ["SM", "Start", "Length", "Control"],
           Enum.map(sm_configs, fn {index, phys_start, length, ctrl} ->
             [
               Integer.to_string(index),
               hex(phys_start, 4),
               Integer.to_string(length),
               hex(ctrl, 8)
             ]
           end)
         ),
         properties_section("Selection", [{"Slave", inspect(slave)}, {"Station", hex(station, 4)}])
       ]}
    end
  end

  defp run_sii_action(:pdo_configs, _attrs, slave, bus, station) do
    with {:ok, pdo_configs} <- SII.read_pdo_configs(bus, station) do
      {:ok,
       [
         table_section(
           "SII PDO Configs",
           ["Direction", "Index", "SM", "Bits", "Bit offset"],
           Enum.map(pdo_configs, fn pdo ->
             [
               Atom.to_string(pdo.direction),
               hex(pdo.index, 4),
               Integer.to_string(pdo.sm_index),
               Integer.to_string(pdo.bit_size),
               Integer.to_string(pdo.bit_offset)
             ]
           end)
         ),
         properties_section("Selection", [{"Slave", inspect(slave)}, {"Station", hex(station, 4)}])
       ]}
    end
  end

  defp run_sii_action(:read_words, attrs, slave, bus, station) do
    with {:ok, word_address} <- integer_value(Map.get(attrs, "sii_word_address")),
         {:ok, word_count} <- integer_value(Map.get(attrs, "sii_word_count")),
         {:ok, binary} <- SII.read(bus, station, word_address, word_count) do
      {:ok,
       [
         properties_section("SII Read Words", [
           {"Slave", inspect(slave)},
           {"Word address", hex(word_address, 4)},
           {"Word count", Integer.to_string(word_count)},
           {"Bytes", Integer.to_string(byte_size(binary))},
           {"Hex", Base.encode16(binary, case: :upper)}
         ])
       ]}
    end
  end

  defp run_sii_action(:write_words, attrs, slave, bus, station) do
    with {:ok, word_address} <- integer_value(Map.get(attrs, "sii_word_address")),
         {:ok, payload} <- binary_value(Map.get(attrs, "sii_write_data")),
         :ok <- SII.write(bus, station, word_address, payload) do
      {:ok,
       [
         properties_section("SII Write Words", [
           {"Slave", inspect(slave)},
           {"Word address", hex(word_address, 4)},
           {"Bytes", Integer.to_string(byte_size(payload))},
           {"Hex", Base.encode16(payload, case: :upper)},
           {"Result", "ok"}
         ])
       ]}
    end
  end

  defp run_sii_action(:dump, _attrs, slave, bus, station) do
    with {:ok, binary} <- SII.dump(bus, station) do
      preview = binary_part(binary, 0, min(byte_size(binary), 64))

      {:ok,
       [
         properties_section("SII Dump", [
           {"Slave", inspect(slave)},
           {"Bytes", Integer.to_string(byte_size(binary))},
           {"Preview hex", Base.encode16(preview, case: :upper)}
         ])
       ]}
    end
  end

  defp run_sii_action(:reload, _attrs, slave, bus, station) do
    with :ok <- SII.reload(bus, station) do
      {:ok,
       [
         properties_section("SII Reload", [
           {"Slave", inspect(slave)},
           {"Station", hex(station, 4)},
           {"Result", "ok"}
         ])
       ]}
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
           register: Registers.al_status(),
           label: "AL status",
           decoder: &Registers.decode_al_status/1
         }}

      "al_status_code" ->
        {:ok, %{register: Registers.al_status_code(), label: "AL status code", decoder: nil}}

      "dl_status" ->
        {:ok, %{register: Registers.dl_status(), label: "DL status", decoder: nil}}

      "rx_error_counter" ->
        {:ok,
         %{
           register: Registers.rx_error_counter(),
           label: "RX error counter",
           decoder: &Registers.decode_rx_errors/1
         }}

      "lost_link_counter" ->
        {:ok,
         %{register: Registers.lost_link_counter(), label: "Lost link counter", decoder: nil}}

      "wdt_status" ->
        {:ok,
         %{
           register: Registers.wdt_status(),
           label: "Watchdog status",
           decoder: &Registers.wdt_status_expired?/1
         }}

      "sm_status" ->
        with {:ok, idx} <- integer_value(channel) do
          {:ok, %{register: Registers.sm_status(idx), label: "SM status", decoder: nil}}
        end

      "sm_activate" ->
        with {:ok, idx} <- integer_value(channel) do
          {:ok, %{register: Registers.sm_activate(idx), label: "SM activate", decoder: nil}}
        end

      _ ->
        {:error, :invalid_register}
    end
  end

  defp raw_read_spec(attrs) do
    with {:ok, address} <- integer_value(Map.get(attrs, "address")),
         {:ok, size} <- integer_value(Map.get(attrs, "size")) do
      {:ok, %{register: {address, size}, label: "Raw register", decoder: nil}}
    end
  end

  defp preset_write_spec(attrs) do
    value = Map.get(attrs, "value")
    channel = Map.get(attrs, "channel")

    case Map.get(attrs, "register", "al_control") do
      "al_control" ->
        with {:ok, encoded} <- integer_value(value) do
          {:ok, %{register: Registers.al_control(encoded), label: "AL control"}}
        end

      "dl_port_control" ->
        with {:ok, encoded} <- integer_value(value) do
          {:ok, %{register: Registers.dl_port_control(encoded), label: "DL port control"}}
        end

      "dl_alias_control" ->
        with {:ok, encoded} <- integer_value(value) do
          {:ok, %{register: Registers.dl_alias_control(encoded), label: "DL alias control"}}
        end

      "ecat_event_mask" ->
        with {:ok, encoded} <- integer_value(value) do
          {:ok, %{register: Registers.ecat_event_mask(encoded), label: "ECAT event mask"}}
        end

      "sm_activate" ->
        with {:ok, idx} <- integer_value(channel),
             {:ok, encoded} <- integer_value(value) do
          {:ok, %{register: Registers.sm_activate(idx, encoded), label: "SM activate"}}
        end

      _ ->
        {:error, :invalid_register}
    end
  end

  defp raw_write_spec(attrs) do
    with {:ok, address} <- integer_value(Map.get(attrs, "address")),
         {:ok, payload} <- binary_value(Map.get(attrs, "write_data")) do
      {:ok, %{register: {address, payload}, label: "Raw register"}}
    end
  end

  defp sii_action(value) when value in @sii_operations, do: {:ok, String.to_existing_atom(value)}
  defp sii_action(_value), do: {:error, :invalid_sii_operation}

  defp slave_atom(value) when is_binary(value) do
    trimmed = String.trim(value)

    if trimmed == "" do
      {:error, :missing_slave}
    else
      {:ok, String.to_existing_atom(trimmed)}
    end
  rescue
    ArgumentError -> {:error, :unknown_slave}
  end

  defp slave_atom(_value), do: {:error, :missing_slave}

  defp integer_value(value) when is_integer(value) and value >= 0, do: {:ok, value}

  defp integer_value(value) when is_binary(value) do
    trimmed = String.trim(value)

    cond do
      trimmed == "" ->
        {:error, :invalid_integer}

      String.starts_with?(String.downcase(trimmed), "0x") ->
        case Integer.parse(String.slice(trimmed, 2..-1//1), 16) do
          {integer, ""} when integer >= 0 -> {:ok, integer}
          _ -> {:error, :invalid_integer}
        end

      true ->
        case Integer.parse(trimmed) do
          {integer, ""} when integer >= 0 -> {:ok, integer}
          _ -> {:error, :invalid_integer}
        end
    end
  end

  defp integer_value(_value), do: {:error, :invalid_integer}

  defp binary_value(value) when is_binary(value) do
    digits =
      value
      |> String.replace(~r/[^0-9A-Fa-f]/u, "")
      |> String.upcase()

    cond do
      digits == "" ->
        {:error, :invalid_binary}

      rem(byte_size(digits), 2) != 0 ->
        {:error, :invalid_binary}

      true ->
        {:ok, Base.decode16!(digits, case: :mixed)}
    end
  end

  defp binary_value(_value), do: {:error, :invalid_binary}

  defp decode_value(nil, _data), do: "n/a"
  defp decode_value(decoder, data) when is_function(decoder, 1), do: inspect(decoder.(data))

  defp properties_section(title, items) do
    %{
      type: "properties",
      title: title,
      items: Enum.map(items, fn {label, value} -> %{label: label, value: value} end)
    }
  end

  defp table_section(title, headers, rows) do
    %{
      type: "table",
      title: title,
      headers: headers,
      rows: rows
    }
  end

  defp hex(integer, pad) when is_integer(integer) and integer >= 0 do
    "0x" <> String.upcase(String.pad_leading(Integer.to_string(integer, 16), pad, "0"))
  end

  defp hex(_integer, _pad), do: "n/a"
end
