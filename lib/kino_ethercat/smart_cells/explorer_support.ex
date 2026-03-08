defmodule KinoEtherCAT.SmartCells.ExplorerSupport do
  @moduledoc false

  @spec slave_suggestions(:all | :coe) :: [map()]
  def slave_suggestions(filter \\ :all) do
    case safe(fn -> EtherCAT.slaves() end, []) do
      slaves when is_list(slaves) ->
        Enum.flat_map(slaves, fn %{name: name, station: station} ->
          case safe(fn -> EtherCAT.slave_info(name) end, {:error, :not_found}) do
            {:ok, info} ->
              if include_slave?(info, filter) do
                [%{value: Atom.to_string(name), label: "#{name} @ #{hex(station, 4)}"}]
              else
                []
              end

            _ ->
              []
          end
        end)

      _ ->
        []
    end
  end

  @spec normalize_selected_slave(String.t() | nil, [map()]) :: String.t()
  def normalize_selected_slave(selected, suggestions) do
    selected =
      case selected do
        nil -> ""
        value -> value |> to_string() |> String.trim()
      end

    valid_values = MapSet.new(Enum.map(suggestions, & &1.value))

    cond do
      selected != "" and
          (MapSet.size(valid_values) == 0 or MapSet.member?(valid_values, selected)) ->
        selected

      suggestions == [] ->
        ""

      true ->
        suggestions
        |> List.first()
        |> Map.fetch!(:value)
    end
  end

  @spec slave_field(String.t(), [map()], String.t()) :: map()
  def slave_field(label, suggestions, help) do
    field_type = if suggestions == [], do: "text", else: "select"

    %{
      name: "slave",
      label: label,
      type: field_type,
      help: help,
      options: suggestions,
      placeholder: "slave_1"
    }
  end

  defp include_slave?(_info, :all), do: true
  defp include_slave?(info, :coe), do: Map.get(info, :coe, false)

  defp safe(fun, default) do
    fun.()
  rescue
    _ -> default
  catch
    :exit, _ -> default
  end

  defp hex(nil, _pad), do: "n/a"

  defp hex(value, pad) do
    "0x" <> String.upcase(String.pad_leading(Integer.to_string(value, 16), pad, "0"))
  end
end
