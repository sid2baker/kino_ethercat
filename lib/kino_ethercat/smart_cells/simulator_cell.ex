defmodule KinoEtherCAT.SmartCells.Simulator do
  use Kino.JS, assets_path: "lib/assets/explorer_cell/build"
  use Kino.JS.Live
  use Kino.SmartCell, name: "EtherCAT Simulator Loopback"

  alias KinoEtherCAT.SmartCells.SimulatorSource

  @default_master_ip "127.0.0.1"
  @default_simulator_ip "127.0.0.2"
  @default_cycle_time_ms "10"

  @impl true
  def init(attrs, ctx) do
    {:ok, assign(ctx, Keyword.new(normalized_assigns(attrs)))}
  end

  @impl true
  def handle_connect(ctx) do
    {:ok, payload(ctx.assigns), ctx}
  end

  @impl true
  def handle_event("update", params, ctx) do
    attrs = Map.merge(to_attrs(ctx), params)
    assigns = normalized_assigns(attrs)
    ctx = assign(ctx, Keyword.new(assigns))
    broadcast_event(ctx, "snapshot", payload(ctx.assigns))
    {:noreply, ctx}
  end

  @impl true
  def to_attrs(ctx) do
    %{
      "master_ip" => ctx.assigns.master_ip,
      "simulator_ip" => ctx.assigns.simulator_ip,
      "cycle_time_ms" => ctx.assigns.cycle_time_ms
    }
  end

  @impl true
  def to_source(attrs) do
    SimulatorSource.render(attrs)
  end

  defp payload(assigns) do
    %{
      title: "Simulator Loopback",
      description:
        "Boot a UDP-backed EK1100 -> EL1809 -> EL2809 simulator ring and wire matching channels for loopback experiments.",
      values: %{
        "master_ip" => assigns.master_ip,
        "simulator_ip" => assigns.simulator_ip,
        "cycle_time_ms" => assigns.cycle_time_ms
      },
      fields: [
        %{
          name: "master_ip",
          label: "Master Bind IP",
          type: "text",
          placeholder: @default_master_ip,
          help: "Local UDP bind IP for the real EtherCAT master runtime."
        },
        %{
          name: "simulator_ip",
          label: "Simulator IP",
          type: "text",
          placeholder: @default_simulator_ip,
          help: "UDP endpoint IP for EtherCAT.Simulator."
        },
        %{
          name: "cycle_time_ms",
          label: "Cycle Time (ms)",
          type: "text",
          placeholder: @default_cycle_time_ms,
          help: "Domain cycle time in whole milliseconds."
        }
      ]
    }
  end

  defp normalized_assigns(attrs) do
    [
      master_ip: string_attr(attrs, "master_ip", @default_master_ip),
      simulator_ip: string_attr(attrs, "simulator_ip", @default_simulator_ip),
      cycle_time_ms: string_attr(attrs, "cycle_time_ms", @default_cycle_time_ms)
    ]
  end

  defp string_attr(attrs, key, default) do
    case Map.get(attrs, key, default) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> default
          trimmed -> trimmed
        end

      value when is_integer(value) ->
        Integer.to_string(value)

      _ ->
        default
    end
  end
end
