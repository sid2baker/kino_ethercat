defmodule KinoEtherCAT.SmartCells.SetupTransport do
  @moduledoc false

  @default_interface "eth0"
  @default_udp_host "127.0.0.2"
  @default_port 0x88A4

  @type t :: %{
          transport: :raw | :udp,
          interface: String.t(),
          host: String.t(),
          port: pos_integer()
        }

  @spec normalize(map()) :: t()
  def normalize(attrs) when is_map(attrs) do
    %{
      transport: normalize_transport(attrs),
      interface: attrs |> Map.get("interface", @default_interface) |> normalize_interface(),
      host: attrs |> Map.get("host", @default_udp_host) |> normalize_host(),
      port: attrs |> Map.get("port", @default_port) |> positive_integer(@default_port)
    }
  end

  @spec runtime_start_opts(t()) :: {:ok, keyword()} | {:error, String.t()}
  def runtime_start_opts(%{transport: :raw, interface: interface})
      when byte_size(interface) > 0 do
    {:ok, [interface: interface]}
  end

  def runtime_start_opts(%{transport: :udp, host: host, port: port}) do
    with {:ok, host_ip} <- parse_required_ip(host, "UDP host") do
      {:ok,
       [transport: :udp, host: host_ip, port: port]
       |> maybe_put_bind_ip(default_bind_ip(host_ip))}
    end
  end

  def runtime_start_opts(_config), do: {:error, "Invalid bus transport configuration."}

  @spec source_config(t()) ::
          {:ok,
           %{
             transport: :raw | :udp,
             interface: String.t(),
             host: :inet.ip_address() | nil,
             port: pos_integer(),
             bind_ip: :inet.ip_address() | nil
           }}
          | {:error, :invalid_transport}
  def source_config(%{transport: :raw, interface: interface}) when byte_size(interface) > 0 do
    {:ok, %{transport: :raw, interface: interface, host: nil, port: @default_port, bind_ip: nil}}
  end

  def source_config(%{transport: :udp, host: host, port: port}) do
    with {:ok, host_ip} <- parse_ip(host) do
      {:ok,
       %{
         transport: :udp,
         interface: "",
         host: host_ip,
         port: port,
         bind_ip: default_bind_ip(host_ip)
       }}
    else
      _ -> {:error, :invalid_transport}
    end
  end

  def source_config(_config), do: {:error, :invalid_transport}

  @spec summary_label(t()) :: String.t()
  def summary_label(%{transport: :raw, interface: interface}) when byte_size(interface) > 0,
    do: interface

  def summary_label(%{transport: :udp, host: host, port: port}) when byte_size(host) > 0,
    do: "#{host}:#{port}"

  def summary_label(%{transport: :udp}), do: "udp:unconfigured"
  def summary_label(_config), do: "n/a"

  defp normalize_transport(attrs) do
    case Map.get(attrs, "transport") do
      value when value in [:udp, "udp"] ->
        :udp

      value when value in [:raw, "raw"] ->
        :raw

      _ ->
        if Enum.any?(~w(host port), &Map.has_key?(attrs, &1)), do: :udp, else: :raw
    end
  end

  defp normalize_interface(value) when is_binary(value) do
    case String.trim(value) do
      "" -> @default_interface
      trimmed -> trimmed
    end
  end

  defp normalize_interface(_value), do: @default_interface

  defp normalize_string(value) when is_binary(value), do: String.trim(value)
  defp normalize_string(_value), do: ""

  defp normalize_host(value) do
    case normalize_string(value) do
      "" -> @default_udp_host
      host -> host
    end
  end

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value

  defp positive_integer(value, default) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> default
    end
  end

  defp positive_integer(_value, default), do: default

  defp parse_required_ip(value, label) do
    case parse_ip(value) do
      {:ok, ip} -> {:ok, ip}
      :error -> {:error, "Invalid #{label}."}
    end
  end

  defp parse_ip(value) when is_binary(value) do
    value = String.trim(value)

    if value == "" do
      :error
    else
      case :inet.parse_address(String.to_charlist(value)) do
        {:ok, ip} -> {:ok, ip}
        _ -> :error
      end
    end
  end

  defp parse_ip(_value), do: :error

  defp default_bind_ip({127, 0, 0, 1}), do: {127, 0, 0, 2}
  defp default_bind_ip({127, _b, _c, _d}), do: {127, 0, 0, 1}
  defp default_bind_ip(_host_ip), do: nil

  defp maybe_put_bind_ip(opts, nil), do: opts
  defp maybe_put_bind_ip(opts, bind_ip), do: Keyword.put(opts, :bind_ip, bind_ip)
end
