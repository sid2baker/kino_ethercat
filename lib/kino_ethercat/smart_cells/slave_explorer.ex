defmodule KinoEtherCAT.SmartCells.SlaveExplorer do
  use Kino.JS, assets_path: "lib/assets/explorer_cell/build"
  use Kino.JS.Live
  use Kino.SmartCell, name: "EtherCAT Slave Explorer"

  alias KinoEtherCAT.SmartCells.{ExplorerSource, ExplorerSupport}

  @surface_options [
    %{value: "register", label: "ESC Registers"},
    %{value: "sdo", label: "CoE SDO"},
    %{value: "sii", label: "SII EEPROM"}
  ]

  @sdo_operations [
    %{value: "upload", label: "Upload"},
    %{value: "download", label: "Download"}
  ]

  @register_read_presets [
    %{value: "al_status", label: "AL status"},
    %{value: "al_status_code", label: "AL status code"},
    %{value: "dl_status", label: "DL status"},
    %{value: "rx_error_counter", label: "RX error counter"},
    %{value: "lost_link_counter", label: "Lost link counter"},
    %{value: "wdt_status", label: "Watchdog status"},
    %{value: "sm_status", label: "SM status"},
    %{value: "sm_activate", label: "SM activate"}
  ]

  @register_write_presets [
    %{value: "al_control", label: "AL control"},
    %{value: "dl_port_control", label: "DL port control"},
    %{value: "dl_alias_control", label: "DL alias control"},
    %{value: "ecat_event_mask", label: "ECAT event mask"},
    %{value: "sm_activate", label: "SM activate"}
  ]

  @sii_operations [
    %{value: "identity", label: "Identity"},
    %{value: "mailbox", label: "Mailbox"},
    %{value: "sync_managers", label: "Sync managers"},
    %{value: "pdo_configs", label: "PDO configs"},
    %{value: "read_words", label: "Read words"},
    %{value: "write_words", label: "Write words"},
    %{value: "dump", label: "Dump EEPROM"},
    %{value: "reload", label: "Reload ESC"}
  ]

  @impl true
  def init(attrs, ctx) do
    assigns = normalized_assigns(attrs)
    {:ok, assign(ctx, Keyword.new(assigns))}
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

  def handle_event("refresh_slaves", _params, ctx) do
    assigns = normalized_assigns(to_attrs(ctx))
    ctx = assign(ctx, Keyword.new(assigns))
    broadcast_event(ctx, "snapshot", payload(ctx.assigns))
    {:noreply, ctx}
  end

  @impl true
  def to_attrs(ctx) do
    %{
      "surface" => ctx.assigns.surface,
      "slave" => ctx.assigns.slave,
      "operation" => ctx.assigns.operation,
      "index" => ctx.assigns.index,
      "subindex" => ctx.assigns.subindex,
      "write_data" => ctx.assigns.write_data,
      "register_mode" => ctx.assigns.register_mode,
      "register" => ctx.assigns.register,
      "channel" => ctx.assigns.channel,
      "address" => ctx.assigns.address,
      "size" => ctx.assigns.size,
      "value" => ctx.assigns.value,
      "word_address" => ctx.assigns.word_address,
      "word_count" => ctx.assigns.word_count
    }
  end

  @impl true
  def to_source(attrs) do
    case surface_from_attrs(attrs) do
      "sdo" -> ExplorerSource.render_sdo(attrs)
      "sii" -> ExplorerSource.render_sii(attrs)
      _ -> ExplorerSource.render_register(attrs)
    end
  end

  defp payload(assigns) do
    %{
      title: "Slave Explorer",
      description: description(assigns.surface),
      actions: [%{id: "refresh_slaves", label: "Refresh bus"}],
      values: values(assigns),
      fields: fields(assigns)
    }
  end

  defp values(assigns) do
    %{
      "surface" => assigns.surface,
      "slave" => assigns.slave,
      "operation" => assigns.operation,
      "index" => assigns.index,
      "subindex" => assigns.subindex,
      "write_data" => assigns.write_data,
      "register_mode" => assigns.register_mode,
      "register" => assigns.register,
      "channel" => assigns.channel,
      "address" => assigns.address,
      "size" => assigns.size,
      "value" => assigns.value,
      "word_address" => assigns.word_address,
      "word_count" => assigns.word_count
    }
  end

  defp fields(assigns) do
    base_fields = [
      %{
        name: "surface",
        label: "Explorer",
        type: "select",
        options: @surface_options,
        help: "Switch between ESC register, CoE mailbox, and SII EEPROM tooling."
      },
      slave_field(assigns.surface, assigns.suggestions)
    ]

    base_fields ++ mode_fields(assigns)
  end

  defp mode_fields(%{surface: "sdo"} = assigns) do
    [
      %{name: "operation", label: "Operation", type: "select", options: @sdo_operations},
      %{
        name: "index",
        label: "Index",
        type: "text",
        placeholder: "0x1018",
        help: "Use decimal or 0x-prefixed hexadecimal."
      },
      %{name: "subindex", label: "Subindex", type: "text", placeholder: "0x00"}
    ] ++ maybe_download_field(assigns.operation)
  end

  defp mode_fields(%{surface: "sii"} = assigns) do
    [
      %{name: "operation", label: "Operation", type: "select", options: @sii_operations}
    ] ++ maybe_word_fields(assigns.operation)
  end

  defp mode_fields(%{surface: "register"} = assigns) do
    [
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
  end

  defp maybe_download_field("download") do
    [
      %{
        name: "write_data",
        label: "Write Data",
        type: "textarea",
        placeholder: "DE AD BE EF",
        help: "Hex bytes separated by spaces, commas, or newlines."
      }
    ]
  end

  defp maybe_download_field(_operation), do: []

  defp maybe_word_fields("read_words") do
    [
      %{name: "word_address", label: "Word Address", type: "text", placeholder: "0x0040"},
      %{name: "word_count", label: "Word Count", type: "text", placeholder: "8"}
    ]
  end

  defp maybe_word_fields("write_words") do
    [
      %{name: "word_address", label: "Word Address", type: "text", placeholder: "0x0040"},
      %{
        name: "write_data",
        label: "Write Data",
        type: "textarea",
        placeholder: "00 00",
        help: "Whole-word payload encoded as hex bytes."
      }
    ]
  end

  defp maybe_word_fields(_operation), do: []

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
      %{name: "register", label: "Preset", type: "select", options: @register_write_presets},
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
      %{name: "register", label: "Preset", type: "select", options: @register_read_presets},
      %{
        name: "channel",
        label: "Channel",
        type: "text",
        placeholder: "0",
        help: "Used by SM status and SM activate."
      }
    ]
  end

  defp description("sdo") do
    "Generate repeatable CoE SDO uploads and downloads against the selected CoE-capable slave."
  end

  defp description("sii") do
    "Inspect or update the slave EEPROM and trigger ESC-side SII reloads from one place."
  end

  defp description(_surface) do
    "Read and write ESC registers, with preset helpers for common AL, DL, watchdog, and sync manager diagnostics."
  end

  defp slave_field("sdo", suggestions) do
    ExplorerSupport.slave_field(
      "Slave",
      suggestions,
      "Select a CoE-capable slave on the active master."
    )
  end

  defp slave_field(_surface, suggestions) do
    ExplorerSupport.slave_field(
      "Slave",
      suggestions,
      "Configured slave name on the active master."
    )
  end

  defp normalized_assigns(attrs) when is_map(attrs) do
    surface = surface_from_attrs(attrs)
    suggestions = ExplorerSupport.slave_suggestions(slave_filter(surface))
    operation = normalize_operation(surface, attrs["operation"])
    register_mode = normalize_register_mode(attrs["register_mode"])

    %{
      surface: surface,
      slave: ExplorerSupport.normalize_selected_slave(attrs["slave"], suggestions),
      operation: operation,
      index: attrs["index"] || "0x1018",
      subindex: attrs["subindex"] || "0x00",
      write_data: attrs["write_data"] || default_write_data(surface),
      register_mode: register_mode,
      register: normalize_register(register_mode, operation, attrs["register"]),
      channel: attrs["channel"] || "0",
      address: attrs["address"] || "0x0130",
      size: attrs["size"] || "2",
      value: attrs["value"] || "0x08",
      word_address: attrs["word_address"] || "0x0040",
      word_count: attrs["word_count"] || "8",
      suggestions: suggestions
    }
  end

  defp surface_from_attrs(attrs) when is_map(attrs) do
    surface = attrs["surface"]
    operation = attrs["operation"]

    cond do
      surface in ["register", "sdo", "sii"] ->
        surface

      Map.has_key?(attrs, "register_mode") or Map.has_key?(attrs, "register") ->
        "register"

      operation in Enum.map(@sii_operations, & &1.value) or
        Map.has_key?(attrs, "word_address") or Map.has_key?(attrs, "word_count") ->
        "sii"

      operation in Enum.map(@sdo_operations, & &1.value) or
        Map.has_key?(attrs, "index") or Map.has_key?(attrs, "subindex") ->
        "sdo"

      true ->
        "register"
    end
  end

  defp surface_from_attrs(_attrs), do: "register"

  defp slave_filter("sdo"), do: :coe
  defp slave_filter(_surface), do: :all

  defp normalize_operation("sdo", operation) when operation in ["upload", "download"],
    do: operation

  defp normalize_operation("sii", operation)
       when operation in [
              "identity",
              "mailbox",
              "sync_managers",
              "pdo_configs",
              "read_words",
              "write_words",
              "dump",
              "reload"
            ],
       do: operation

  defp normalize_operation("register", operation) when operation in ["read", "write"],
    do: operation

  defp normalize_operation("sdo", _operation), do: "upload"
  defp normalize_operation("sii", _operation), do: "identity"
  defp normalize_operation(_surface, _operation), do: "read"

  defp normalize_register_mode(mode) when mode in ["preset", "raw"], do: mode
  defp normalize_register_mode(_mode), do: "preset"

  defp normalize_register("raw", _operation, register), do: register || ""

  defp normalize_register("preset", "write", register)
       when register in [
              "al_control",
              "dl_port_control",
              "dl_alias_control",
              "ecat_event_mask",
              "sm_activate"
            ],
       do: register

  defp normalize_register("preset", "read", register)
       when register in [
              "al_status",
              "al_status_code",
              "dl_status",
              "rx_error_counter",
              "lost_link_counter",
              "wdt_status",
              "sm_status",
              "sm_activate"
            ],
       do: register

  defp normalize_register("preset", "write", _register), do: "al_control"
  defp normalize_register("preset", _operation, _register), do: "al_status"

  defp default_write_data("sii"), do: "00 00"
  defp default_write_data("register"), do: "08 00"
  defp default_write_data(_surface), do: ""
end
