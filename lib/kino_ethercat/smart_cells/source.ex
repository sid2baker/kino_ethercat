defmodule KinoEtherCAT.Source do
  @moduledoc false

  @module_pattern ~r/^(Elixir\.)?[A-Z][A-Za-z0-9_]*(\.[A-Z][A-Za-z0-9_]*)*$/
  @atom_pattern ~r/^[a-z_][A-Za-z0-9_]*[!?]?$/

  @spec atom_literal(String.t()) :: String.t()
  def atom_literal(name) when is_binary(name) do
    trimmed = String.trim(name)

    if Regex.match?(@atom_pattern, trimmed) do
      ":" <> trimmed
    else
      ":" <> inspect(trimmed)
    end
  end

  @spec module_literal(String.t()) :: {:ok, String.t()} | :error
  def module_literal(source) when is_binary(source) do
    source = String.trim(source)

    if Regex.match?(@module_pattern, source) do
      {:ok, source}
    else
      :error
    end
  end

  @spec integer_literal(integer()) :: String.t()
  def integer_literal(value) when is_integer(value) do
    Integer.to_string(value)
  end

  @spec multiline(iodata()) :: String.t()
  def multiline(lines) do
    lines
    |> IO.iodata_to_binary()
    |> String.trim()
    |> Kernel.<>("\n")
  end
end
