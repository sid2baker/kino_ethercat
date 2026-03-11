defmodule KinoEtherCAT.SmartCells.SimulatorConfig do
  @moduledoc false

  alias KinoEtherCAT.Driver

  @default_simulator_ip "127.0.0.2"
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

  @spec normalize(map()) :: %{simulator_ip: String.t(), selected: [map()]}
  def normalize(attrs) when is_map(attrs) do
    available_modules =
      available_drivers()
      |> Enum.map(& &1.module)
      |> MapSet.new()

    selected =
      attrs
      |> Map.get("selected")
      |> normalize_selected(available_modules)
      |> ensure_default_selected(available_modules)

    %{
      simulator_ip: normalize_simulator_ip(Map.get(attrs, "simulator_ip")),
      selected: selected
    }
  end

  @spec normalize_simulator_ip(term()) :: String.t()
  def normalize_simulator_ip(value), do: string_attr(value, @default_simulator_ip)

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

        {device_name, counts} = next_device_name(driver_info.default_name, counts)

        {%{id: id, driver: driver, label: driver_info.label, default_name: device_name}, counts}
      end)

    entries
  end

  defp normalize_selected(selected, available_modules) when is_list(selected) do
    selected
    |> Enum.map(&normalize_selected_entry/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&MapSet.member?(available_modules, &1["driver"]))
    |> Enum.with_index(1)
    |> Enum.map(fn {entry, index} ->
      %{"id" => Integer.to_string(index), "driver" => Map.fetch!(entry, "driver")}
    end)
  end

  defp normalize_selected(_selected, _available_modules), do: []

  defp normalize_selected_entry(%{"driver" => driver}) when is_binary(driver),
    do: %{"driver" => driver}

  defp normalize_selected_entry(driver) when is_binary(driver),
    do: %{"driver" => driver}

  defp normalize_selected_entry(_entry), do: nil

  defp ensure_default_selected([], available_modules) do
    @default_driver_modules
    |> Enum.map(&module_string/1)
    |> Enum.filter(&MapSet.member?(available_modules, &1))
    |> Enum.with_index(1)
    |> Enum.map(fn {driver, index} ->
      %{"id" => Integer.to_string(index), "driver" => driver}
    end)
  end

  defp ensure_default_selected(selected, _available_modules), do: selected

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

  defp string_attr(value, default) when is_binary(value) do
    case String.trim(value) do
      "" -> default
      trimmed -> trimmed
    end
  end

  defp string_attr(_value, default), do: default
end
