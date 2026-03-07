defmodule KinoEtherCAT.StartCell do
  use Kino.JS, assets_path: "lib/assets/start_cell/build"
  use Kino.JS.Live
  use Kino.SmartCell, name: "EtherCAT Start"

  @impl true
  def init(attrs, ctx) do
    slaves = attrs["slaves"] || []
    status = if slaves == [], do: :idle, else: :discovered

    {:ok,
     assign(ctx,
       interface: attrs["interface"] || "eth0",
       status: status,
       error: nil,
       slaves: slaves,
       domain_id: attrs["domain_id"] || "main",
       cycle_time_us: attrs["cycle_time_us"] || 1_000
     )}
  end

  @impl true
  def handle_connect(ctx) do
    {:ok,
     %{
       interface: ctx.assigns.interface,
       status: to_string(ctx.assigns.status),
       error: ctx.assigns.error,
       slaves: ctx.assigns.slaves,
       domain_id: ctx.assigns.domain_id,
       cycle_time_us: ctx.assigns.cycle_time_us
     }, ctx}
  end

  @impl true
  def handle_event("scan", _params, ctx) do
    server = self()
    interface = ctx.assigns.interface
    Task.start(fn -> run_scan(server, interface) end)
    broadcast_event(ctx, "status", %{status: "scanning"})
    {:noreply, assign(ctx, status: :scanning, error: nil)}
  end

  def handle_event("update_interface", %{"interface" => iface}, ctx) do
    {:noreply, assign(ctx, interface: iface)}
  end

  def handle_event("update_slave", %{"index" => idx, "name" => name, "driver" => driver}, ctx) do
    slaves =
      List.update_at(
        ctx.assigns.slaves,
        idx,
        &Map.merge(&1, %{"name" => name, "driver" => driver})
      )

    {:noreply, assign(ctx, slaves: slaves)}
  end

  def handle_event(
        "update_domain",
        %{"domain_id" => domain_id, "cycle_time_us" => cycle_time_us},
        ctx
      ) do
    {:noreply, assign(ctx, domain_id: domain_id, cycle_time_us: cycle_time_us)}
  end

  @impl true
  def handle_info({:scan_complete, {:ok, slaves}}, ctx) do
    broadcast_event(ctx, "scan_result", %{slaves: slaves})
    {:noreply, assign(ctx, status: :discovered, slaves: slaves, error: nil)}
  end

  def handle_info({:scan_complete, {:error, reason}}, ctx) do
    broadcast_event(ctx, "scan_error", %{error: reason})
    {:noreply, assign(ctx, status: :error, error: reason)}
  end

  @impl true
  def to_attrs(ctx) do
    %{
      "interface" => ctx.assigns.interface,
      "slaves" => ctx.assigns.slaves,
      "domain_id" => ctx.assigns.domain_id,
      "cycle_time_us" => ctx.assigns.cycle_time_us
    }
  end

  @impl true
  def to_source(attrs) do
    interface = attrs["interface"] || ""
    slaves = attrs["slaves"] || []

    if interface == "" or Enum.empty?(slaves) do
      ""
    else
      domain_id = String.to_atom(attrs["domain_id"] || "main")
      cycle_time_us = attrs["cycle_time_us"] || 1_000

      domain_struct =
        quote do: %DomainConfig{id: unquote(domain_id), cycle_time_us: unquote(cycle_time_us)}

      slave_structs = Enum.map(slaves, &slave_quoted(&1, domain_id))

      ast =
        quote do
          alias EtherCAT.Slave.Config, as: SlaveConfig
          alias EtherCAT.Domain.Config, as: DomainConfig

          EtherCAT.start(
            interface: unquote(interface),
            domains: [unquote(domain_struct)],
            slaves: unquote(slave_structs)
          )
        end

      Kino.SmartCell.quoted_to_string(ast)
    end
  end

  defp slave_quoted(%{"name" => name, "driver" => driver}, domain_id)
       when is_binary(driver) and driver != "" do
    name_atom = String.to_atom(name)

    case Code.string_to_quoted(driver) do
      {:ok, driver_ast} ->
        quote do
          %SlaveConfig{
            name: unquote(name_atom),
            driver: unquote(driver_ast),
            process_data: {:all, unquote(domain_id)}
          }
        end

      {:error, _} ->
        quote do: %SlaveConfig{name: unquote(name_atom)}
    end
  end

  defp slave_quoted(%{"name" => name}, _domain_id) do
    name_atom = String.to_atom(name)
    quote do: %SlaveConfig{name: unquote(name_atom)}
  end

  defp run_scan(server, interface) do
    result =
      with :ok <- EtherCAT.start(interface: interface),
           :ok <- EtherCAT.await_running(15_000) do
        slaves =
          EtherCAT.slaves()
          |> Enum.with_index(1)
          |> Enum.map(fn {{name, station, _pid}, idx} ->
            identity =
              case EtherCAT.slave_info(name) do
                {:ok, %{identity: id}} when not is_nil(id) -> id
                _ -> %{}
              end

            %{
              "station" => station,
              "vendor_id" => Map.get(identity, :vendor_id, 0),
              "product_code" => Map.get(identity, :product_code, 0),
              "name" => "slave_#{idx}",
              "driver" => ""
            }
          end)

        EtherCAT.stop()
        {:ok, slaves}
      else
        {:error, reason} ->
          EtherCAT.stop()
          {:error, inspect(reason)}
      end

    send(server, {:scan_complete, result})
  rescue
    e ->
      EtherCAT.stop()
      send(server, {:scan_complete, {:error, Exception.message(e)}})
  end
end
