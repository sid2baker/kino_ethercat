defmodule KinoEtherCAT.SmartCells.BusSetup do
  @moduledoc false

  alias KinoEtherCAT.SmartCells.SetupTransport

  @spec available_interfaces() :: [String.t()]
  def available_interfaces do
    "/sys/class/net"
    |> File.ls()
    |> case do
      {:ok, interfaces} ->
        interfaces
        |> Enum.reject(&(&1 == "lo"))
        |> Enum.sort()

      {:error, _reason} ->
        []
    end
  end

  @spec runtime_state() :: atom()
  def runtime_state do
    case EtherCAT.state() do
      {:ok, state} when is_atom(state) -> state
      _ -> :idle
    end
  rescue
    _ -> :idle
  end

  @spec transport_assigns(map() | keyword()) :: SetupTransport.t()
  def transport_assigns(assigns) when is_map(assigns) do
    %{
      transport_mode: Map.fetch!(assigns, :transport_mode),
      transport: Map.fetch!(assigns, :transport),
      interface: Map.fetch!(assigns, :interface),
      backup_interface: Map.fetch!(assigns, :backup_interface),
      host: Map.fetch!(assigns, :host),
      port: Map.fetch!(assigns, :port)
    }
  end

  def transport_assigns(assigns) when is_list(assigns) do
    assigns
    |> Map.new()
    |> transport_assigns()
  end

  @spec transport_changed?(map() | keyword(), SetupTransport.t()) :: boolean()
  def transport_changed?(assigns, transport) do
    current = transport_assigns(assigns)

    current.transport_mode != transport.transport_mode or
      current.transport != transport.transport or
      current.interface != transport.interface or
      current.backup_interface != transport.backup_interface or
      current.host != transport.host or
      current.port != transport.port
  end

  @spec format_pid(pid() | term()) :: String.t() | nil
  def format_pid(pid) when is_pid(pid), do: inspect(pid)
  def format_pid(_pid), do: nil
end
