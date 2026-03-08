defmodule KinoEtherCAT.SetupCell do
  use Kino.JS, assets_path: "lib/assets/setup_cell/build"
  use Kino.JS.Live
  use Kino.SmartCell, name: "EtherCAT Setup"

  alias KinoEtherCAT.Source

  @impl true
  def init(attrs, ctx) do
    slaves = attrs["slaves"] || []
    status = if slaves == [], do: :idle, else: :discovered
    Process.send_after(self(), :poll_phase, 500)

    {:ok,
     assign(ctx,
       interface: attrs["interface"] || "eth0",
       status: status,
       error: nil,
       slaves: slaves,
       domain_id: attrs["domain_id"] || "main",
       cycle_time_us: attrs["cycle_time_us"] || 1_000,
       master_phase: :idle
     )}
  end

  @impl true
  def handle_connect(ctx) do
    drivers =
      Enum.map(KinoEtherCAT.Driver.all(), fn %{module: mod, name: name} ->
        %{module: inspect(mod), name: name}
      end)

    {:ok,
     %{
       interface: ctx.assigns.interface,
       status: to_string(ctx.assigns.status),
       error: ctx.assigns.error,
       slaves: ctx.assigns.slaves,
       domain_id: ctx.assigns.domain_id,
       cycle_time_us: ctx.assigns.cycle_time_us,
       master_phase: to_string(ctx.assigns.master_phase),
       available_drivers: drivers
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

  def handle_event("stop", _params, ctx) do
    _ = EtherCAT.stop()
    broadcast_event(ctx, "status", %{status: "idle"})
    {:noreply, assign(ctx, status: :idle, error: nil)}
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

  def handle_info(:poll_phase, ctx) do
    Process.send_after(self(), :poll_phase, 2_000)
    phase = EtherCAT.phase()

    if phase != ctx.assigns.master_phase do
      broadcast_event(ctx, "master_phase", %{phase: to_string(phase)})
      {:noreply, assign(ctx, master_phase: phase)}
    else
      {:noreply, ctx}
    end
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
    interface =
      attrs
      |> Map.get("interface", "")
      |> String.trim()

    slaves = attrs["slaves"] || []

    if interface == "" or Enum.empty?(slaves) do
      ""
    else
      domain_id =
        attrs
        |> Map.get("domain_id", "main")
        |> String.trim()

      cycle_time_us =
        attrs
        |> Map.get("cycle_time_us", 1_000)
        |> normalize_cycle_time()

      slave_structs =
        slaves
        |> Enum.map(&slave_source(&1, domain_id))
        |> Enum.reject(&is_nil/1)
        |> Enum.join(",\n")

      Source.multiline([
        "alias EtherCAT.Slave.Config, as: SlaveConfig\n",
        "alias EtherCAT.Domain.Config, as: DomainConfig\n\n",
        "EtherCAT.stop()\n\n",
        "EtherCAT.start(\n",
        "  interface: ",
        inspect(interface),
        ",\n",
        "  domains: [%DomainConfig{id: ",
        Source.atom_literal(domain_id),
        ", cycle_time_us: ",
        Source.integer_literal(cycle_time_us),
        "}],\n",
        "  slaves: [\n",
        indent_lines(slave_structs, 4),
        "\n",
        "  ]\n",
        ")\n"
      ])
    end
  end

  defp slave_source(%{"name" => name} = slave, domain_id) when is_binary(name) do
    name = String.trim(name)

    if name == "" do
      nil
    else
      fields =
        case driver_source(slave["driver"]) do
          {:ok, driver_source} ->
            [
              "name: ",
              Source.atom_literal(name),
              ", driver: ",
              driver_source,
              ", process_data: {:all, ",
              Source.atom_literal(domain_id),
              "}"
            ]

          :error ->
            ["name: ", Source.atom_literal(name)]
        end

      IO.iodata_to_binary(["%SlaveConfig{", fields, "}"])
    end
  end

  defp driver_source(driver) when is_binary(driver) do
    Source.module_literal(driver)
  end

  defp driver_source(_driver), do: :error

  defp normalize_cycle_time(value) when is_integer(value) and value > 0, do: value

  defp normalize_cycle_time(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> 1_000
    end
  end

  defp normalize_cycle_time(_value), do: 1_000

  defp indent_lines("", _spaces), do: ""

  defp indent_lines(content, spaces) do
    padding = String.duplicate(" ", spaces)

    content
    |> String.split("\n")
    |> Enum.map_join("\n", &(padding <> &1))
  end

  defp run_scan(server, interface) do
    result =
      with :ok <- EtherCAT.start(interface: interface),
           :ok <- EtherCAT.await_running(15_000) do
        slaves =
          EtherCAT.slaves()
          |> Enum.with_index(1)
          |> Enum.map(fn {%{name: name, station: station}, idx} ->
            identity =
              case EtherCAT.slave_info(name) do
                {:ok, %{identity: id}} when not is_nil(id) -> id
                _ -> %{}
              end

            driver =
              case KinoEtherCAT.Driver.lookup(identity) do
                {:ok, %{module: mod}} -> inspect(mod)
                :error -> ""
              end

            %{
              "station" => station,
              "vendor_id" => Map.get(identity, :vendor_id, 0),
              "product_code" => Map.get(identity, :product_code, 0),
              "name" => "slave_#{idx}",
              "driver" => driver
            }
          end)

        {:ok, slaves}
      else
        {:error, reason} -> {:error, inspect(reason)}
      end

    send(server, {:scan_complete, result})
  rescue
    e -> send(server, {:scan_complete, {:error, Exception.message(e)}})
  end
end
