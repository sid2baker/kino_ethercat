defmodule KinoEtherCAT.SmartCells.SimulatorConfig do
  @moduledoc false

  alias KinoEtherCAT.Driver
  alias EtherCAT.Simulator.Slave

  @default_simulator_ip "127.0.0.2"
  @default_port 0x88A4
  @default_driver_modules [
    KinoEtherCAT.Driver.EK1100,
    KinoEtherCAT.Driver.EL1809,
    KinoEtherCAT.Driver.EL2809
  ]
  @default_names %{
    "KinoEtherCAT.Driver.EK1100" => "coupler",
    "KinoEtherCAT.Driver.EL1809" => "inputs",
    "KinoEtherCAT.Driver.EL2809" => "outputs"
  }

  @spec default_simulator_ip() :: String.t()
  def default_simulator_ip, do: @default_simulator_ip

  @spec default_port() :: pos_integer()
  def default_port, do: @default_port

  @spec available_drivers() :: [map()]
  def available_drivers do
    Driver.simulator_all()
    |> Enum.map(fn entry ->
      module = module_string(entry.module)

      %{
        module: module,
        label: entry.name,
        default_name: default_name(module)
      }
    end)
  end

  @spec default_selected() :: [map()]
  def default_selected do
    ensure_default_selected([], available_driver_modules())
  end

  @spec default_connections([map()]) :: [map()]
  def default_connections(selected) when is_list(selected) do
    devices = device_entries(selected)

    with %{id: source_id, signal: source_signal, bit_size: bit_size} <-
           Enum.find(signal_refs_by_name(devices, :output, "ch1"), &match?(%{bit_size: 1}, &1)),
         %{id: target_id, signal: target_signal, bit_size: ^bit_size} <-
           Enum.find(signal_refs_by_name(devices, :input, "ch1"), &match?(%{bit_size: 1}, &1)) do
      [
        %{
          "source_id" => source_id,
          "source_signal" => source_signal,
          "target_id" => target_id,
          "target_signal" => target_signal
        }
      ]
    else
      _ -> []
    end
  end

  @spec normalize(map()) :: %{selected: [map()], connections: [map()]}
  def normalize(attrs) when is_map(attrs) do
    selected =
      attrs
      |> Map.get("selected")
      |> normalize_selected(available_driver_modules())
      |> ensure_default_selected(available_driver_modules())

    connections =
      attrs
      |> initial_connections(selected)
      |> normalize_connections(selected)

    %{
      selected: selected,
      connections: connections
    }
  end

  @spec valid_driver?(String.t()) :: boolean()
  def valid_driver?(driver) when is_binary(driver) do
    available_drivers()
    |> Enum.any?(&(&1.module == driver))
  end

  def valid_driver?(_driver), do: false

  @spec selected_entries([map()]) :: [map()]
  def selected_entries(selected) when is_list(selected) do
    drivers = Map.new(available_drivers(), &{&1.module, &1})

    {entries, _counts} =
      Enum.map_reduce(selected, %{}, fn entry, counts ->
        driver = Map.get(entry, "driver")
        id = Map.get(entry, "id")

        driver_info =
          Map.get(drivers, driver, %{
            label: module_label(driver),
            default_name: default_name(driver)
          })

        requested_name = Map.get(entry, "name") || driver_info.default_name
        {device_name, counts} = next_device_name(requested_name, counts)

        {
          %{
            id: id,
            driver: driver,
            label: driver_info.label,
            name: device_name,
            default_name: driver_info.default_name
          },
          counts
        }
      end)

    entries
  end

  @spec connection_entries([map()], [map()]) :: [map()]
  def connection_entries(selected, connections)
      when is_list(selected) and is_list(connections) do
    devices = Map.new(device_entries(selected), &{&1.id, &1})

    connections
    |> normalize_connections(selected)
    |> Enum.map(fn connection ->
      source = Map.fetch!(devices, connection["source_id"])
      target = Map.fetch!(devices, connection["target_id"])

      %{
        key:
          connection_key(
            connection["source_id"],
            connection["source_signal"],
            connection["target_id"],
            connection["target_signal"]
          ),
        source_id: connection["source_id"],
        source_signal: connection["source_signal"],
        target_id: connection["target_id"],
        target_signal: connection["target_signal"],
        source_name: source.name,
        target_name: target.name,
        source_label: "#{source.name}.#{connection["source_signal"]}",
        target_label: "#{target.name}.#{connection["target_signal"]}"
      }
    end)
  end

  @spec auto_wire_matching([map()]) :: {connections :: [map()], stats :: map()}
  def auto_wire_matching(selected) when is_list(selected) do
    devices = device_entries(selected)
    outputs = Enum.flat_map(devices, &signal_refs(&1, :output))
    inputs_by_name = Enum.group_by(Enum.flat_map(devices, &signal_refs(&1, :input)), & &1.signal)

    {connections, output_count, input_count} =
      Enum.reduce(outputs, {[], 0, 0}, fn output, {acc, output_count, input_count} ->
        case Enum.filter(
               Map.get(inputs_by_name, output.signal, []),
               &(&1.bit_size == output.bit_size)
             ) do
          [input] ->
            connection = %{
              "source_id" => output.id,
              "source_signal" => output.signal,
              "target_id" => input.id,
              "target_signal" => input.signal
            }

            {[connection | acc], output_count + 1, input_count + 1}

          _ ->
            {acc, output_count + 1, input_count}
        end
      end)

    normalized = normalize_connections(Enum.reverse(connections), selected)

    {normalized,
     %{
       matched: length(normalized),
       output_signals: output_count,
       input_candidates: input_count
     }}
  end

  defp normalize_selected(selected, available_modules) when is_list(selected) do
    selected
    |> Enum.map(&normalize_selected_entry/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&MapSet.member?(available_modules, &1["driver"]))
    |> Enum.with_index(1)
    |> Enum.map(fn {entry, index} ->
      %{
        "id" => Integer.to_string(index),
        "driver" => Map.fetch!(entry, "driver"),
        "name" => Map.get(entry, "name")
      }
    end)
    |> normalize_selected_names()
  end

  defp normalize_selected(_selected, _available_modules), do: []

  defp normalize_selected_entry(%{"driver" => driver} = entry) when is_binary(driver) do
    %{"driver" => driver, "name" => normalize_name(Map.get(entry, "name"))}
  end

  defp normalize_selected_entry(driver) when is_binary(driver),
    do: %{"driver" => driver, "name" => nil}

  defp normalize_selected_entry(_entry), do: nil

  defp ensure_default_selected([], available_modules) do
    @default_driver_modules
    |> Enum.map(&module_string/1)
    |> Enum.filter(&MapSet.member?(available_modules, &1))
    |> Enum.with_index(1)
    |> Enum.map(fn {driver, index} ->
      %{"id" => Integer.to_string(index), "driver" => driver, "name" => default_name(driver)}
    end)
  end

  defp ensure_default_selected(selected, _available_modules), do: selected

  defp normalize_selected_names(selected) when is_list(selected) do
    {entries, _counts} =
      Enum.map_reduce(selected, %{}, fn entry, counts ->
        driver = Map.get(entry, "driver")
        requested_name = Map.get(entry, "name") || default_name(driver)
        {name, counts} = next_device_name(requested_name, counts)
        {Map.put(entry, "name", name), counts}
      end)

    entries
  end

  defp normalize_connections(connections, selected) when is_list(connections) do
    devices = Map.new(device_entries(selected), &{&1.id, &1})

    connections
    |> Enum.map(&normalize_connection_entry/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&valid_connection?(&1, devices))
    |> Enum.uniq_by(fn connection ->
      connection_key(
        connection["source_id"],
        connection["source_signal"],
        connection["target_id"],
        connection["target_signal"]
      )
    end)
  end

  defp normalize_connections(_connections, _selected), do: []

  defp initial_connections(attrs, selected) when is_map(attrs) do
    if Map.has_key?(attrs, "connections") do
      Map.get(attrs, "connections", [])
    else
      default_connections(selected)
    end
  end

  defp available_driver_modules do
    available_drivers()
    |> Enum.map(& &1.module)
    |> MapSet.new()
  end

  defp device_entries(selected) do
    selected_entries(selected)
    |> Enum.map(fn entry ->
      Map.put(entry, :signals, signal_entries(entry.driver))
    end)
  end

  defp signal_entries(driver) when is_binary(driver) do
    with {:ok, module} <- driver_module(driver),
         device <- Slave.from_driver(module, name: :sim),
         definitions when is_map(definitions) <- Slave.signal_definitions(device) do
      definitions
      |> Enum.map(fn {signal_name, definition} ->
        %{
          name: to_string(signal_name),
          direction: Map.get(definition, :direction),
          bit_size: Map.get(definition, :bit_size)
        }
      end)
      |> Enum.sort_by(fn signal ->
        {direction_rank(signal.direction), natural_signal_key(signal.name)}
      end)
    else
      _ -> []
    end
  end

  defp signal_entries(_driver), do: []

  defp signal_refs(device, direction) do
    device.signals
    |> Enum.filter(&(&1.direction == direction))
    |> Enum.map(fn signal ->
      %{
        id: device.id,
        name: device.name,
        signal: signal.name,
        bit_size: signal.bit_size
      }
    end)
  end

  defp signal_refs_by_name(devices, direction, signal_name) do
    devices
    |> Enum.flat_map(&signal_refs(&1, direction))
    |> Enum.filter(&(&1.signal == signal_name))
  end

  defp normalize_connection_entry(%{
         "source_id" => source_id,
         "source_signal" => source_signal,
         "target_id" => target_id,
         "target_signal" => target_signal
       })
       when is_binary(source_id) and is_binary(source_signal) and is_binary(target_id) and
              is_binary(target_signal) do
    %{
      "source_id" => source_id,
      "source_signal" => String.trim(source_signal),
      "target_id" => target_id,
      "target_signal" => String.trim(target_signal)
    }
  end

  defp normalize_connection_entry(_entry), do: nil

  defp valid_connection?(connection, devices) do
    source = Map.get(devices, connection["source_id"])
    target = Map.get(devices, connection["target_id"])

    not is_nil(source) and not is_nil(target) and
      source.id != target.id and
      signal_present?(source.signals, connection["source_signal"], :output) and
      signal_present?(target.signals, connection["target_signal"], :input)
  end

  defp signal_present?(signals, signal_name, direction) do
    Enum.any?(signals, &(&1.name == signal_name and &1.direction == direction))
  end

  defp driver_module(driver) do
    Driver.simulator_all()
    |> Enum.find_value(:error, fn entry ->
      if module_string(entry.module) == driver, do: {:ok, entry.module}, else: false
    end)
  end

  defp connection_key(source_id, source_signal, target_id, target_signal) do
    "#{source_id}.#{source_signal}->#{target_id}.#{target_signal}"
  end

  defp normalize_name(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_name(_value), do: nil

  defp direction_rank(:output), do: 0
  defp direction_rank(:input), do: 1
  defp direction_rank(_direction), do: 2

  defp natural_signal_key(name) when is_binary(name) do
    case Regex.run(~r/^(.*?)(\d+)$/, name, capture: :all_but_first) do
      [prefix, digits] -> {prefix, String.length(digits), String.to_integer(digits), name}
      _ -> {name, 0, 0, name}
    end
  end

  defp default_name(module) do
    Map.get(@default_names, module, module |> module_label() |> String.downcase())
  end

  defp module_label(module) when is_binary(module) do
    module
    |> String.split(".")
    |> List.last()
    |> to_string()
  end

  defp module_string(module) when is_atom(module) do
    module
    |> Module.split()
    |> Enum.join(".")
  end

  defp next_device_name(base_name, counts) do
    occurrence = Map.get(counts, base_name, 0) + 1
    name = if occurrence == 1, do: base_name, else: "#{base_name}_#{occurrence}"
    {name, Map.put(counts, base_name, occurrence)}
  end
end
