defmodule KinoEtherCAT.Testing.Scenario do
  @moduledoc false

  alias KinoEtherCAT.Testing.Step

  @enforce_keys [:name]
  defstruct name: nil,
            description: nil,
            timeout_ms: 30_000,
            tags: [],
            steps: []

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t() | nil,
          timeout_ms: pos_integer(),
          tags: [String.t()],
          steps: [Step.t()]
        }

  @spec new(String.t(), keyword()) :: t()
  def new(name, opts \\ []) when is_binary(name) do
    %__MODULE__{
      name: String.trim(name),
      description: normalize_string(Keyword.get(opts, :description)),
      timeout_ms: Keyword.get(opts, :timeout_ms, 30_000),
      tags: normalize_tags(Keyword.get(opts, :tags, [])),
      steps: []
    }
  end

  @spec add_step(t(), Step.t()) :: t()
  def add_step(%__MODULE__{} = scenario, %Step{} = step) do
    %{scenario | steps: scenario.steps ++ [step]}
  end

  defp normalize_tags(tags) when is_list(tags) do
    tags
    |> Enum.map(&normalize_string/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_tags(_tags), do: []

  defp normalize_string(nil), do: nil

  defp normalize_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_string(value), do: to_string(value)
end
