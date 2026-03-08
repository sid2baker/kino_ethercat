defmodule KinoEtherCAT.RegisterExplorer do
  use Kino.JS, assets_path: "lib/assets/explorer_cell/build"
  use Kino.JS.Live
  use Kino.SmartCell, name: "EtherCAT Register Explorer"

  alias KinoEtherCAT.{ExplorerSource, ExplorerSupport}

  @read_presets [
    %{value: "al_status", label: "AL status"},
    %{value: "al_status_code", label: "AL status code"},
    %{value: "dl_status", label: "DL status"},
    %{value: "rx_error_counter", label: "RX error counter"},
    %{value: "lost_link_counter", label: "Lost link counter"},
    %{value: "wdt_status", label: "Watchdog status"},
    %{value: "sm_status", label: "SM status"},
    %{value: "sm_activate", label: "SM activate"}
  ]

  @write_presets [
    %{value: "al_control", label: "AL control"},
    %{value: "dl_port_control", label: "DL port control"},
    %{value: "dl_alias_control", label: "DL alias control"},
    %{value: "ecat_event_mask", label: "ECAT event mask"},
    %{value: "sm_activate", label: "SM activate"}
  ]

  @impl true
  def init(attrs, ctx) do
    suggestions = ExplorerSupport.slave_suggestions(:all)

    {:ok,
     assign(ctx,
       slave: ExplorerSupport.normalize_selected_slave(attrs["slave"], suggestions),
       operation: attrs["operation"] || "read",
       register_mode: attrs["register_mode"] || "preset",
       register: attrs["register"] || "al_status",
       channel: attrs["channel"] || "0",
       address: attrs["address"] || "0x0130",
       size: attrs["size"] || "2",
       value: attrs["value"] || "0x08",
       write_data: attrs["write_data"] || "08 00",
       suggestions: suggestions
     )}
  end

  @impl true
  def handle_connect(ctx) do
    {:ok, payload(ctx.assigns), ctx}
  end

  @impl true
  def handle_event("update", params, ctx) do
    ctx =
      assign(ctx,
        slave: Map.get(params, "slave", ctx.assigns.slave),
        operation: Map.get(params, "operation", ctx.assigns.operation),
        register_mode: Map.get(params, "register_mode", ctx.assigns.register_mode),
        register: Map.get(params, "register", ctx.assigns.register),
        channel: Map.get(params, "channel", ctx.assigns.channel),
        address: Map.get(params, "address", ctx.assigns.address),
        size: Map.get(params, "size", ctx.assigns.size),
        value: Map.get(params, "value", ctx.assigns.value),
        write_data: Map.get(params, "write_data", ctx.assigns.write_data)
      )

    broadcast_event(ctx, "snapshot", payload(ctx.assigns))
    {:noreply, ctx}
  end

  def handle_event("refresh_slaves", _params, ctx) do
    suggestions = ExplorerSupport.slave_suggestions(:all)

    ctx =
      assign(ctx,
        suggestions: suggestions,
        slave: ExplorerSupport.normalize_selected_slave(ctx.assigns.slave, suggestions)
      )

    broadcast_event(ctx, "snapshot", payload(ctx.assigns))
    {:noreply, ctx}
  end

  @impl true
  def to_attrs(ctx) do
    %{
      "slave" => ctx.assigns.slave,
      "operation" => ctx.assigns.operation,
      "register_mode" => ctx.assigns.register_mode,
      "register" => ctx.assigns.register,
      "channel" => ctx.assigns.channel,
      "address" => ctx.assigns.address,
      "size" => ctx.assigns.size,
      "value" => ctx.assigns.value,
      "write_data" => ctx.assigns.write_data
    }
  end

  @impl true
  def to_source(attrs) do
    ExplorerSource.render_register(attrs)
  end

  defp payload(assigns) do
    %{
      title: "ESC Registers",
      description:
        "Generate raw ESC register reads and writes, with preset helpers for common diagnostics.",
      actions: [%{id: "refresh_slaves", label: "Refresh bus"}],
      values: %{
        "slave" => assigns.slave,
        "operation" => assigns.operation,
        "register_mode" => assigns.register_mode,
        "register" => assigns.register,
        "channel" => assigns.channel,
        "address" => assigns.address,
        "size" => assigns.size,
        "value" => assigns.value,
        "write_data" => assigns.write_data
      },
      fields:
        [
          %{
            name: "slave",
            label: "Slave",
            type: "datalist",
            help: "Configured slave name on the active master.",
            options: assigns.suggestions,
            placeholder: "slave_1"
          },
          %{
            name: "operation",
            label: "Operation",
            type: "select",
            options: [%{value: "read", label: "Read"}, %{value: "write", label: "Write"}]
          },
          %{
            name: "register_mode",
            label: "Addressing",
            type: "select",
            options: [%{value: "preset", label: "Preset"}, %{value: "raw", label: "Raw"}]
          }
        ] ++ register_fields(assigns)
    }
  end

  defp register_fields(%{register_mode: "raw", operation: "write"} = assigns) do
    [
      %{name: "address", label: "Address", type: "text", placeholder: "0x0120"},
      %{
        name: "write_data",
        label: "Write Data",
        type: "textarea",
        placeholder: assigns.write_data,
        help: "Hex bytes written directly to the configured address."
      }
    ]
  end

  defp register_fields(%{register_mode: "raw"}) do
    [
      %{name: "address", label: "Address", type: "text", placeholder: "0x0130"},
      %{name: "size", label: "Size", type: "text", placeholder: "2"}
    ]
  end

  defp register_fields(%{operation: "write"} = assigns) do
    [
      %{name: "register", label: "Preset", type: "select", options: @write_presets},
      %{
        name: "channel",
        label: "Channel",
        type: "text",
        placeholder: "0",
        help: "Used by SM activate."
      },
      %{
        name: "value",
        label: "Value",
        type: "text",
        placeholder: assigns.value,
        help: "Decimal or 0x-prefixed hex."
      }
    ]
  end

  defp register_fields(_assigns) do
    [
      %{name: "register", label: "Preset", type: "select", options: @read_presets},
      %{
        name: "channel",
        label: "Channel",
        type: "text",
        placeholder: "0",
        help: "Used by SM status and SM activate."
      }
    ]
  end
end
