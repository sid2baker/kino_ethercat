defmodule KinoEtherCAT.Widgets.SlaveSnapshot do
  @moduledoc false

  @spec build(atom(), map() | nil, map(), [map()], map() | nil, term() | nil, keyword()) :: map()
  def build(slave_name, info, values, domain_snapshots, write_error, runtime_error, opts \\ [])

  def build(slave_name, nil, _values, _domain_snapshots, write_error, runtime_error, opts) do
    %{
      status: "unavailable",
      summary: %{
        name: Keyword.get(opts, :title, to_string(slave_name)),
        station: nil,
        al_state: "unavailable",
        driver: nil,
        coe: nil,
        configuration_error: nil,
        identity: nil
      },
      domains: [],
      inputs: [],
      outputs: [],
      write_error: format_write_error(write_error),
      runtime_error: format_reason(runtime_error)
    }
  end

  def build(slave_name, info, values, domain_snapshots, write_error, runtime_error, opts) do
    {inputs, outputs} =
      info.signals
      |> Enum.map(&signal_view(&1, values))
      |> Enum.split_with(&(&1.direction == "input"))

    %{
      status: status(runtime_error),
      summary: %{
        name: Keyword.get(opts, :title, to_string(info.name || slave_name)),
        station: info.station,
        al_state: to_string(info.al_state || :unknown),
        driver: format_driver(info.driver),
        coe: info.coe,
        configuration_error: format_reason(info.configuration_error),
        identity: maybe_identity(info.identity, opts)
      },
      domains: maybe_domains(domain_snapshots, opts),
      inputs: inputs,
      outputs: outputs,
      write_error: format_write_error(write_error),
      runtime_error: format_reason(runtime_error)
    }
  end

  defp signal_view(signal, values) do
    known? = Map.has_key?(values, signal.name)
    sample = Map.get(values, signal.name)
    value = sample_value(sample)
    bit_signal? = signal.bit_size == 1

    %{
      name: to_string(signal.name),
      direction: to_string(signal.direction),
      domain: to_string(signal.domain),
      bit_size: signal.bit_size,
      kind: if(bit_signal?, do: "bit", else: "value"),
      known: known?,
      active: if(bit_signal? and known?, do: active?(value), else: nil),
      display: display_value(value, known?),
      updated_at_us: updated_at_us(sample),
      writable: signal.direction == :output and bit_signal?
    }
  end

  defp maybe_identity(identity, opts) do
    if Keyword.get(opts, :show_identity?, true), do: identity, else: nil
  end

  defp maybe_domains(domain_snapshots, opts) do
    if Keyword.get(opts, :show_domains?, true), do: domain_snapshots, else: []
  end

  defp status(nil), do: "live"
  defp status(_runtime_error), do: "stale"

  defp format_driver(nil), do: nil
  defp format_driver(driver), do: inspect(driver)

  defp format_write_error(nil), do: nil

  defp format_write_error(%{signal: signal, reason: reason}) do
    %{signal: to_string(signal), reason: format_reason(reason)}
  end

  defp format_reason(nil), do: nil
  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)

  defp display_value(_value, false), do: "awaiting data"
  defp display_value(value, true), do: inspect(value, pretty: false, limit: 8)

  defp sample_value({value, updated_at_us}) when is_integer(updated_at_us), do: value
  defp sample_value(value), do: value

  defp updated_at_us({_value, updated_at_us}) when is_integer(updated_at_us), do: updated_at_us
  defp updated_at_us(_value), do: nil

  defp active?(true), do: true
  defp active?(false), do: false
  defp active?(value) when is_integer(value), do: value != 0
  defp active?(value) when is_float(value), do: value != 0.0
  defp active?(value), do: value not in [nil, "", :off]
end
