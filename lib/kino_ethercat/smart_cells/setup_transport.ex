defmodule KinoEtherCAT.SmartCells.SetupTransport do
  @moduledoc false

  alias KinoEtherCAT.SmartCells.SimulatorConfig

  @default_interface "eth0"
  @default_backup_interface "eth1"
  @default_udp_host "127.0.0.2"
  @default_port 0x88A4

  @type t :: %{
          transport_mode: :auto | :manual,
          transport: :raw | :raw_redundant | :udp,
          interface: String.t(),
          backup_interface: String.t(),
          host: String.t(),
          port: pos_integer()
        }

  @spec normalize(map()) :: t()
  def normalize(attrs) when is_map(attrs) do
    %{
      transport_mode: normalize_transport_mode(attrs),
      transport: normalize_transport(attrs),
      interface: attrs |> Map.get("interface", @default_interface) |> normalize_interface(),
      backup_interface:
        attrs
        |> Map.get("backup_interface", @default_backup_interface)
        |> normalize_interface(@default_backup_interface),
      host: attrs |> Map.get("host", @default_udp_host) |> normalize_host(),
      port: attrs |> Map.get("port", @default_port) |> positive_integer(@default_port)
    }
    |> refresh_auto()
  end

  @spec refresh_auto(t()) :: t()
  def refresh_auto(%{transport_mode: :auto} = config) do
    case {auto_seedable?(config), simulator_transport()} do
      {true, {:ok, simulator}} -> Map.merge(config, simulator)
      _ -> config
    end
  end

  def refresh_auto(config), do: config

  defp auto_seedable?(%{transport: :raw, interface: interface}) do
    interface == @default_interface
  end

  defp auto_seedable?(%{
         transport: :raw_redundant,
         interface: interface,
         backup_interface: backup_interface
       }) do
    interface == @default_interface and backup_interface == @default_backup_interface
  end

  defp auto_seedable?(%{transport: :udp, host: host, port: port}) do
    host == @default_udp_host and port == @default_port
  end

  defp auto_seedable?(_config), do: false

  @spec runtime_start_opts(t()) :: {:ok, keyword()} | {:error, String.t()}
  def runtime_start_opts(%{transport: :raw, interface: interface})
      when byte_size(interface) > 0 do
    {:ok, [interface: interface]}
  end

  def runtime_start_opts(%{
        transport: :raw_redundant,
        interface: interface,
        backup_interface: backup_interface
      })
      when byte_size(interface) > 0 and byte_size(backup_interface) > 0 do
    {:ok, [interface: interface, backup_interface: backup_interface]}
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
             transport: :raw | :raw_redundant | :udp,
             interface: String.t(),
             backup_interface: String.t() | nil,
             host: :inet.ip_address() | nil,
             port: pos_integer(),
             bind_ip: :inet.ip_address() | nil
           }}
          | {:error, :invalid_transport}
  def source_config(%{transport: :raw, interface: interface}) when byte_size(interface) > 0 do
    {:ok,
     %{
       transport: :raw,
       interface: interface,
       backup_interface: nil,
       host: nil,
       port: @default_port,
       bind_ip: nil
     }}
  end

  def source_config(%{
        transport: :raw_redundant,
        interface: interface,
        backup_interface: backup_interface
      })
      when byte_size(interface) > 0 and byte_size(backup_interface) > 0 do
    {:ok,
     %{
       transport: :raw_redundant,
       interface: interface,
       backup_interface: backup_interface,
       host: nil,
       port: @default_port,
       bind_ip: nil
     }}
  end

  def source_config(%{transport: :udp, host: host, port: port}) do
    with {:ok, host_ip} <- parse_ip(host) do
      {:ok,
       %{
         transport: :udp,
         interface: "",
         backup_interface: nil,
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

  def summary_label(%{
        transport: :raw_redundant,
        interface: interface,
        backup_interface: backup_interface
      })
      when byte_size(interface) > 0 and byte_size(backup_interface) > 0,
      do: "#{interface} + #{backup_interface}"

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

      value when value in [:raw_redundant, "raw_redundant"] ->
        :raw_redundant

      _ ->
        if Enum.any?(~w(host port), &Map.has_key?(attrs, &1)), do: :udp, else: :raw
    end
  end

  defp normalize_transport_mode(attrs) do
    case Map.get(attrs, "transport_mode") do
      value when value in [:manual, "manual"] ->
        :manual

      value when value in [:auto, "auto"] ->
        :auto

      _ ->
        infer_transport_mode(attrs)
    end
  end

  defp infer_transport_mode(attrs) do
    transport = normalize_transport(attrs)
    interface = attrs |> Map.get("interface", @default_interface) |> normalize_interface()

    backup_interface =
      attrs
      |> Map.get("backup_interface", @default_backup_interface)
      |> normalize_interface(@default_backup_interface)

    host = attrs |> Map.get("host", @default_udp_host) |> normalize_host()
    port = attrs |> Map.get("port", @default_port) |> positive_integer(@default_port)

    cond do
      transport == :raw and interface != @default_interface ->
        :manual

      transport == :raw_redundant and
          (interface != @default_interface or backup_interface != @default_backup_interface) ->
        :manual

      transport == :udp and (host != @default_udp_host or port != @default_port) ->
        :manual

      true ->
        :auto
    end
  end

  defp normalize_interface(value, default \\ @default_interface)

  defp normalize_interface(value, default) when is_binary(value) do
    case String.trim(value) do
      "" -> default
      trimmed -> trimmed
    end
  end

  defp normalize_interface(_value, default), do: default

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

  defp simulator_transport do
    case EtherCAT.Simulator.info() do
      {:ok, %{udp: %{ip: ip, port: port}}} ->
        {:ok, %{transport: :udp, host: format_ip(ip), port: port}}

      {:ok, %{raw: %{interface: interface}}} ->
        raw_transport(interface)

      {:ok, %{raw: %{primary: %{interface: primary}, secondary: %{interface: secondary}}}} ->
        redundant_raw_transport(primary, secondary)

      _ ->
        :error
    end
  rescue
    _ -> :error
  end

  defp format_ip(ip) do
    ip
    |> :inet.ntoa()
    |> to_string()
  end

  defp raw_transport(interface) when is_binary(interface) do
    if interface == SimulatorConfig.raw_simulator_interface() do
      {:ok,
       %{
         transport: :raw,
         interface: SimulatorConfig.raw_master_interface(),
         backup_interface: @default_backup_interface
       }}
    else
      :error
    end
  end

  defp raw_transport(_interface), do: :error

  defp redundant_raw_transport(primary, secondary)
       when is_binary(primary) and is_binary(secondary) do
    if primary == SimulatorConfig.redundant_simulator_primary_interface() and
         secondary == SimulatorConfig.redundant_simulator_secondary_interface() do
      {:ok,
       %{
         transport: :raw_redundant,
         interface: SimulatorConfig.redundant_master_primary_interface(),
         backup_interface: SimulatorConfig.redundant_master_secondary_interface()
       }}
    else
      :error
    end
  end

  defp redundant_raw_transport(_primary, _secondary), do: :error

  defp maybe_put_bind_ip(opts, nil), do: opts
  defp maybe_put_bind_ip(opts, bind_ip), do: Keyword.put(opts, :bind_ip, bind_ip)
end
