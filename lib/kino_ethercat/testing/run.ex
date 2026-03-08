defmodule KinoEtherCAT.Testing.Run do
  @moduledoc false

  alias KinoEtherCAT.Testing.Scenario

  @enforce_keys [:scenario, :options]
  defstruct [:scenario, :options]

  @type option_group :: :bus | :dc | :domain | :slave

  @type options :: %{
          attach_telemetry?: boolean(),
          telemetry_groups: [option_group()]
        }

  @type t :: %__MODULE__{
          scenario: Scenario.t(),
          options: options()
        }

  @spec normalize_options(keyword() | map()) :: options()
  def normalize_options(opts) when is_list(opts) do
    normalize_options(Map.new(opts))
  end

  def normalize_options(opts) when is_map(opts) do
    %{
      attach_telemetry?:
        opts
        |> Map.get(:attach_telemetry?, Map.get(opts, :attach_telemetry, false))
        |> truthy?(),
      telemetry_groups:
        opts
        |> Map.get(:telemetry_groups, [])
        |> normalize_telemetry_groups()
    }
  end

  defp normalize_telemetry_groups(groups) when is_list(groups) do
    groups
    |> Enum.map(&normalize_telemetry_group/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp normalize_telemetry_groups(_groups), do: []

  defp normalize_telemetry_group(group) when group in [:bus, :dc, :domain, :slave], do: group

  defp normalize_telemetry_group(group) when is_binary(group) do
    try do
      normalize_telemetry_group(String.to_existing_atom(group))
    rescue
      ArgumentError -> nil
    end
  end

  defp normalize_telemetry_group(_group), do: nil

  defp truthy?(value) when value in [true, "true", "on", 1], do: true
  defp truthy?(_value), do: false
end
