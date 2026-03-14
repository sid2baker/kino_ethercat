defmodule KinoEtherCAT.SmartCells.SlaveExplorer do
  use Kino.JS, assets_path: "lib/assets/slave_explorer_cell/build"
  use Kino.JS.Live
  use Kino.SmartCell, name: "EtherCAT Slave Explorer"

  alias EtherCAT.Capture

  alias KinoEtherCAT.SmartCells.{
    BusSetup,
    ExplorerRuntime,
    ExplorerSource,
    ExplorerSupport,
    Setup,
    SetupTransport
  }

  @scan_await_timeout_ms 30_000
  @scan_poll_interval_ms 2_000

  @surface_options [
    %{value: "capture", label: "Capture"},
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
    if should_auto_scan?(attrs, assigns), do: Process.send_after(self(), :auto_scan, 0)
    Process.send_after(self(), :poll_state, @scan_poll_interval_ms)
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
    if ctx.assigns.surface == "capture" do
      {:noreply, begin_capture_scan(ctx)}
    else
      assigns = normalized_assigns(to_attrs(ctx))
      ctx = assign(ctx, Keyword.new(assigns))
      broadcast_event(ctx, "snapshot", payload(ctx.assigns))
      {:noreply, ctx}
    end
  end

  def handle_event("run_register", _params, ctx) do
    {:noreply, run_inspection(ctx, &ExplorerRuntime.run_register/1)}
  end

  def handle_event("run_sdo", _params, ctx) do
    {:noreply, run_inspection(ctx, &ExplorerRuntime.run_sdo/1)}
  end

  def handle_event("run_sii", _params, ctx) do
    {:noreply, run_inspection(ctx, &ExplorerRuntime.run_sii/1)}
  end

  @impl true
  def handle_info({:capture_scan_complete, result}, ctx) do
    error =
      case result do
        :ok -> nil
        {:error, reason} -> inspect(reason)
      end

    refresh_capture_context(ctx, error)
  end

  def handle_info(:auto_scan, ctx) do
    if ctx.assigns.surface == "capture" and ctx.assigns.capture_inventory == [] and
         ctx.assigns.capture_master_state in [:idle, :not_started] do
      {:noreply, begin_capture_scan(ctx)}
    else
      {:noreply, ctx}
    end
  end

  def handle_info(:poll_state, ctx) do
    Process.send_after(self(), :poll_state, @scan_poll_interval_ms)

    if ctx.assigns.surface == "capture" do
      state = capture_master_state()
      inventory = capture_inventory("capture")
      suggestions = capture_suggestions(inventory)
      slave = ExplorerSupport.normalize_selected_slave(ctx.assigns.slave, suggestions)

      if state != ctx.assigns.capture_master_state or inventory != ctx.assigns.capture_inventory or
           slave != ctx.assigns.slave do
        ctx =
          ctx
          |> assign(
            capture_master_state: state,
            capture_inventory: inventory,
            capture_suggestions: suggestions,
            slave: slave
          )
          |> refresh_capture_preview()

        broadcast_event(ctx, "snapshot", payload(ctx.assigns))
        {:noreply, ctx}
      else
        {:noreply, ctx}
      end
    else
      {:noreply, ctx}
    end
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
      "word_count" => ctx.assigns.word_count,
      "transport_mode" => Atom.to_string(ctx.assigns.transport_mode),
      "transport" => Atom.to_string(ctx.assigns.transport),
      "interface" => ctx.assigns.interface,
      "backup_interface" => ctx.assigns.backup_interface,
      "host" => ctx.assigns.host,
      "port" => ctx.assigns.port,
      "driver_name" => ctx.assigns.driver_name,
      "capture_sdos" => ctx.assigns.capture_sdos,
      "sdo_operation" => ctx.assigns.sdo_operation,
      "sdo_index" => ctx.assigns.sdo_index,
      "sdo_subindex" => ctx.assigns.sdo_subindex,
      "sdo_write_data" => ctx.assigns.sdo_write_data,
      "sii_operation" => ctx.assigns.sii_operation,
      "sii_word_address" => ctx.assigns.sii_word_address,
      "sii_word_count" => ctx.assigns.sii_word_count,
      "sii_write_data" => ctx.assigns.sii_write_data,
      "signal_names" => ctx.assigns.signal_names,
      "capture_signal_entries" => ctx.assigns.capture_signal_entries,
      "capture_snapshot" => ctx.assigns.capture_snapshot
    }
  end

  @impl true
  def to_source(attrs) do
    case surface_from_attrs(attrs) do
      "capture" -> ExplorerSource.render_capture(attrs)
      "sdo" -> ExplorerSource.render_sdo(attrs)
      "sii" -> ExplorerSource.render_sii(attrs)
      _ -> ExplorerSource.render_register(attrs)
    end
  end

  defp payload(assigns) do
    transport = capture_transport(assigns)

    %{
      title: title(assigns.surface),
      description: description(assigns.surface),
      actions: [%{id: "refresh_slaves", label: refresh_label(assigns.surface)}],
      bus: %{
        transport: Atom.to_string(assigns.transport),
        interface: assigns.interface,
        backup_interface: assigns.backup_interface,
        host: assigns.host,
        port: assigns.port,
        available_interfaces: assigns.available_interfaces,
        transport_source: SetupTransport.summary_label(transport)
      },
      capture: %{
        slave: assigns.slave,
        inventory: assigns.capture_inventory,
        suggestions: assigns.capture_suggestions,
        sections: assigns.capture_sections,
        signal_entries: assigns.capture_signal_entries,
        scan_status: Atom.to_string(assigns.capture_scan_status),
        error: assigns.capture_error,
        master_state: Atom.to_string(assigns.capture_master_state)
      },
      scaffold: %{
        driver_name: assigns.driver_name,
        driver_module: assigns.driver_module,
        simulator_module: assigns.simulator_module,
        capture_sdos: assigns.capture_sdos
      },
      inspection: %{
        register: %{
          operation: assigns.operation,
          register_mode: assigns.register_mode,
          register: assigns.register,
          channel: assigns.channel,
          address: assigns.address,
          size: assigns.size,
          value: assigns.value,
          write_data: assigns.write_data
        },
        sdo: %{
          operation: assigns.sdo_operation,
          index: assigns.sdo_index,
          subindex: assigns.sdo_subindex,
          write_data: assigns.sdo_write_data
        },
        sii: %{
          operation: assigns.sii_operation,
          word_address: assigns.sii_word_address,
          word_count: assigns.sii_word_count,
          write_data: assigns.sii_write_data
        },
        sections: assigns.inspection_sections
      },
      values: values(assigns),
      fields: fields(assigns),
      sections: sections(assigns)
    }
  end

  defp values(assigns) do
    base = %{
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
      "word_count" => assigns.word_count,
      "transport" => Atom.to_string(assigns.transport),
      "interface" => assigns.interface,
      "backup_interface" => assigns.backup_interface,
      "host" => assigns.host,
      "port" => assigns.port,
      "driver_name" => assigns.driver_name,
      "capture_sdos" => assigns.capture_sdos,
      "sdo_operation" => assigns.sdo_operation,
      "sdo_index" => assigns.sdo_index,
      "sdo_subindex" => assigns.sdo_subindex,
      "sdo_write_data" => assigns.sdo_write_data,
      "sii_operation" => assigns.sii_operation,
      "sii_word_address" => assigns.sii_word_address,
      "sii_word_count" => assigns.sii_word_count,
      "sii_write_data" => assigns.sii_write_data
    }

    capture_signal_values =
      assigns.capture_signal_entries
      |> Enum.into(%{}, fn entry ->
        {capture_signal_field_name(entry.key), entry.name}
      end)

    Map.merge(base, capture_signal_values)
  end

  defp fields(assigns) do
    if assigns.surface == "capture" do
      capture_fields(assigns)
    else
      generic_fields(assigns)
    end
  end

  defp generic_fields(assigns) do
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

  defp capture_fields(assigns) do
    [
      %{
        name: "surface",
        label: "Tool",
        type: "select",
        section: "Capture Workflow",
        options: @surface_options,
        help:
          "Capture is the main workflow for understanding an unknown slave and scaffolding a driver."
      },
      %{
        name: "transport",
        label: "Transport",
        type: "select",
        section: "Capture Session",
        options: capture_transport_options(),
        help: "Used when the explorer starts its own temporary PREOP capture session."
      },
      %{
        name: "interface",
        label: "Interface",
        type: "text",
        section: "Capture Session",
        placeholder: "eth0",
        help: "Primary raw interface."
      },
      %{
        name: "backup_interface",
        label: "Backup Interface",
        type: "text",
        section: "Capture Session",
        placeholder: "eth1",
        help: "Used only in redundant raw mode."
      },
      %{
        name: "host",
        label: "UDP Host",
        type: "text",
        section: "Capture Session",
        placeholder: "127.0.0.2",
        help: "Used only in UDP mode."
      },
      %{
        name: "port",
        label: "UDP Port",
        type: "text",
        section: "Capture Session",
        placeholder: "34980",
        help: "Used only in UDP mode."
      },
      %{
        name: "slave",
        label: "Selected Slave",
        type: "select",
        section: "Capture Workflow",
        options: capture_slave_options(assigns.capture_suggestions),
        placeholder: "slave_1",
        help: "Pick a discovered slave after scanning the bus."
      },
      %{
        name: "driver_name",
        label: "Driver Name",
        type: "text",
        section: "Scaffold",
        placeholder: capture_driver_name_placeholder(assigns.slave),
        help:
          "Generated modules are derived as EtherCAT.Drivers.<name> and EtherCAT.Drivers.<name>.Simulator."
      },
      %{
        name: "capture_sdos",
        label: "SDOs",
        type: "textarea",
        section: "Optional SDO Snapshot",
        placeholder: "0x1008:0x00\n0x1009:0x00",
        help: "Optional object entries to include in the capture and scaffold."
      }
    ] ++ capture_signal_fields(assigns.capture_signal_entries)
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

  defp description("capture") do
    "Scan a PREOP capture session, inspect one slave, rename PDO-derived signals, and generate best-effort driver and simulator modules."
  end

  defp description(_surface) do
    "Read and write ESC registers, with preset helpers for common AL, DL, watchdog, and sync manager diagnostics."
  end

  defp title("capture"), do: "Slave Capture"
  defp title(_surface), do: "Slave Explorer"

  defp refresh_label("capture"), do: "Scan bus"
  defp refresh_label(_surface), do: "Refresh bus"

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

  defp sections(%{surface: "capture"} = assigns) do
    [
      capture_session_section(assigns),
      capture_inventory_section(assigns.capture_inventory) | assigns.capture_sections
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp sections(_assigns), do: []

  defp normalized_assigns(attrs) when is_map(attrs) do
    surface = surface_from_attrs(attrs)
    transport = SetupTransport.normalize(attrs)
    capture_inventory = capture_inventory(surface)

    suggestions =
      case surface do
        "capture" -> capture_suggestions(capture_inventory)
        _ -> ExplorerSupport.slave_suggestions(slave_filter(surface))
      end

    operation = normalize_operation(surface, attrs["operation"])
    register_mode = normalize_register_mode(attrs["register_mode"])
    slave = ExplorerSupport.normalize_selected_slave(attrs["slave"], suggestions)
    signal_names = normalize_capture_signal_names(attrs)

    capture_preview =
      build_capture_preview(
        surface,
        slave,
        capture_inventory,
        attrs["capture_sdos"] || "",
        signal_names
      )

    %{
      surface: surface,
      slave: slave,
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
      transport_mode: transport.transport_mode,
      transport: transport.transport,
      interface: transport.interface,
      backup_interface: transport.backup_interface,
      host: transport.host,
      port: transport.port,
      driver_name: capture_driver_name(attrs["driver_name"], slave),
      driver_module:
        attrs["driver_name"]
        |> capture_driver_name(slave)
        |> capture_driver_module(),
      simulator_module:
        attrs["driver_name"]
        |> capture_driver_name(slave)
        |> capture_simulator_module(),
      capture_sdos: attrs["capture_sdos"] || "",
      sdo_operation: normalize_sdo_operation(attrs["sdo_operation"]),
      sdo_index: attrs["sdo_index"] || "0x1018",
      sdo_subindex: attrs["sdo_subindex"] || "0x00",
      sdo_write_data: attrs["sdo_write_data"] || "",
      sii_operation: normalize_sii_operation(attrs["sii_operation"]),
      sii_word_address: attrs["sii_word_address"] || "0x0040",
      sii_word_count: attrs["sii_word_count"] || "8",
      sii_write_data: attrs["sii_write_data"] || "00 00",
      available_interfaces: BusSetup.available_interfaces(),
      capture_master_state: capture_master_state(),
      capture_scan_status: if(capture_inventory == [], do: :idle, else: :ready),
      capture_error: nil,
      inspection_sections: [],
      suggestions: suggestions,
      capture_suggestions: capture_suggestions(capture_inventory),
      capture_inventory: capture_inventory,
      capture_sections: capture_preview.sections,
      capture_signal_entries: capture_preview.signal_entries,
      signal_names: capture_preview.signal_names,
      capture_snapshot: capture_preview.snapshot
    }
  end

  defp surface_from_attrs(attrs) when is_map(attrs) do
    surface = attrs["surface"]
    operation = attrs["operation"]

    cond do
      surface in ["register", "sdo", "sii", "capture"] ->
        surface

      Map.has_key?(attrs, "register_mode") or Map.has_key?(attrs, "register") ->
        "register"

      operation in Enum.map(@sii_operations, & &1.value) or
        Map.has_key?(attrs, "word_address") or Map.has_key?(attrs, "word_count") ->
        "sii"

      Map.has_key?(attrs, "driver_name") or Map.has_key?(attrs, "capture_sdos") ->
        "capture"

      operation in Enum.map(@sdo_operations, & &1.value) or
        Map.has_key?(attrs, "index") or Map.has_key?(attrs, "subindex") ->
        "sdo"

      map_size(attrs) == 0 ->
        "capture"

      true ->
        "capture"
    end
  end

  defp surface_from_attrs(_attrs), do: "capture"

  defp slave_filter("sdo"), do: :coe
  defp slave_filter(_surface), do: :all

  defp normalize_operation("capture", _operation), do: "generate"

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

  defp normalize_sdo_operation(operation) when operation in ["upload", "download"], do: operation
  defp normalize_sdo_operation(_operation), do: "upload"

  defp normalize_sii_operation(operation)
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

  defp normalize_sii_operation(_operation), do: "identity"

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

  defp capture_transport_options do
    [
      %{value: "raw", label: "Raw socket"},
      %{value: "raw_redundant", label: "Raw socket + redundant"},
      %{value: "udp", label: "UDP"}
    ]
  end

  defp capture_slave_options([]), do: [%{value: "", label: "No discovered slaves"}]
  defp capture_slave_options(suggestions), do: suggestions

  defp capture_driver_name_placeholder(""), do: "Device"

  defp capture_driver_name_placeholder(slave) do
    case normalize_capture_driver_name(slave) do
      "" -> "Device"
      normalized -> normalized
    end
  end

  defp capture_driver_name(value, slave) when is_binary(value) do
    case normalize_capture_driver_name(value) do
      "" -> capture_driver_name_placeholder(slave)
      normalized -> normalized
    end
  end

  defp capture_driver_name(_value, slave), do: capture_driver_name_placeholder(slave)

  defp capture_driver_module(driver_name) when is_binary(driver_name) do
    "EtherCAT.Drivers." <> driver_name
  end

  defp capture_simulator_module(driver_name) when is_binary(driver_name) do
    capture_driver_module(driver_name) <> ".Simulator"
  end

  defp normalize_capture_driver_name(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.trim_leading("Elixir.")
    |> String.replace_prefix("EtherCAT.Drivers.", "")
    |> String.replace_suffix(".Simulator", "")
    |> String.split(".", trim: true)
    |> Enum.map(&normalize_capture_driver_name_segment/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(".")
  end

  defp normalize_capture_driver_name(_value), do: ""

  defp normalize_capture_driver_name_segment(segment) do
    trimmed = String.trim(segment)

    cond do
      trimmed == "" ->
        ""

      String.match?(trimmed, ~r/^[A-Z][A-Za-z0-9_]*$/) ->
        trimmed

      true ->
        trimmed
        |> Macro.camelize()
        |> ensure_driver_name_segment()
    end
  end

  defp ensure_driver_name_segment(""), do: ""

  defp ensure_driver_name_segment(segment) do
    if String.match?(segment, ~r/^[A-Z][A-Za-z0-9_]*$/) do
      segment
    else
      "Device" <> segment
    end
  end

  defp capture_fields_title(entry) do
    direction =
      case entry.direction do
        "input" -> "Input"
        "output" -> "Output"
        other -> Macro.camelize(other)
      end

    "#{direction} PDO #{hex(entry.pdo_index, 4)}"
  end

  defp capture_signal_fields(entries) do
    Enum.map(entries, fn entry ->
      %{
        name: capture_signal_field_name(entry.key),
        label: entry.default_name,
        type: "text",
        section: "Signal Names",
        placeholder: entry.default_name,
        help:
          "#{capture_fields_title(entry)} • #{entry.bit_size} bit#{if entry.bit_size == 1, do: "", else: "s"} • #{entry.label}"
      }
    end)
  end

  defp capture_signal_field_name(key), do: "capture_signal_name::#{key}"

  defp capture_inventory("capture") do
    case Capture.list_slaves() do
      {:ok, slaves} ->
        Enum.map(slaves, fn slave ->
          %{
            atom: slave.name,
            value: Atom.to_string(slave.name),
            station: slave.station,
            al_state: slave.al_state,
            vendor_id: slave.vendor_id,
            product_code: slave.product_code,
            revision: slave.revision,
            coe: slave.coe,
            fault: slave.fault,
            label:
              "#{slave.name} @ #{hex(slave.station, 4)} • #{hex(slave.vendor_id, 8)}/#{hex(slave.product_code, 8)}"
          }
        end)

      _ ->
        []
    end
  rescue
    _ -> []
  end

  defp capture_inventory(_surface), do: []

  defp capture_master_state do
    case EtherCAT.state() do
      {:ok, state} -> state
      {:error, :not_started} -> :not_started
      {:error, _reason} -> :not_started
    end
  rescue
    _ -> :not_started
  end

  defp capture_suggestions(inventory) do
    Enum.map(inventory, fn slave -> %{value: slave.value, label: slave.label} end)
  end

  defp build_capture_preview("capture", slave, inventory, capture_sdos, signal_names) do
    with %{atom: slave_atom} = selected <- Enum.find(inventory, &(&1.value == slave)),
         {:ok, capture} <- capture_snapshot(slave_atom, capture_sdos),
         definition_options <- Capture.definition_options(capture) do
      signal_entries = capture_signal_entries(definition_options, signal_names)

      %{
        sections: capture_sections(selected, capture, signal_entries),
        signal_entries: signal_entries,
        signal_names: Map.new(signal_entries, &{&1.key, &1.name}),
        snapshot: encode_capture_snapshot(capture)
      }
    else
      nil ->
        %{
          sections: [
            %{
              type: "message",
              title: "Capture",
              tone: "info",
              text: "Pick a slave to inspect it."
            }
          ],
          signal_entries: [],
          signal_names: %{},
          snapshot: nil
        }

      {:error, reason} ->
        %{
          sections: [
            %{
              type: "message",
              title: "Capture",
              tone: "error",
              text: "Failed to capture slave: #{inspect(reason)}"
            }
          ],
          signal_entries: [],
          signal_names: signal_names,
          snapshot: nil
        }
    end
  end

  defp build_capture_preview(_surface, _slave, _inventory, _capture_sdos, signal_names) do
    %{sections: [], signal_entries: [], signal_names: signal_names, snapshot: nil}
  end

  defp capture_snapshot(slave_atom, capture_sdos) do
    sdos = parse_capture_sdos(capture_sdos)
    opts = if sdos == [], do: [], else: [sdos: sdos]
    Capture.capture(slave_atom, opts)
  end

  defp capture_signal_entries(definition_options, signal_names) do
    definition_options
    |> Keyword.get(:signals, %{})
    |> Enum.map(fn {name, spec} ->
      key = capture_signal_key(spec.direction, spec.pdo_index)
      default_name = Atom.to_string(name)

      %{
        key: key,
        name: resolved_capture_signal_name(signal_names, key, default_name),
        default_name: default_name,
        direction: Atom.to_string(spec.direction),
        pdo_index: spec.pdo_index,
        bit_size: spec.bit_size,
        label: Map.get(spec, :label, "PDO #{hex(spec.pdo_index, 4)}")
      }
    end)
    |> Enum.sort_by(fn entry ->
      {capture_direction_rank(entry.direction), entry.pdo_index, entry.default_name}
    end)
  end

  defp capture_signal_key(direction, pdo_index),
    do: "#{direction}:#{String.downcase(Integer.to_string(pdo_index, 16))}"

  defp capture_direction_rank("output"), do: 0
  defp capture_direction_rank("input"), do: 1
  defp capture_direction_rank(_direction), do: 2

  defp capture_sections(selected, capture, signal_entries) do
    mailbox_config = get_in(capture, [:sii, :mailbox_config]) || %{}
    sm_configs = get_in(capture, [:sii, :sm_configs]) || []
    pdo_configs = get_in(capture, [:sii, :pdo_configs]) || []
    definition_options = Capture.definition_options(capture)
    warnings = Map.get(capture, :warnings, [])

    [
      %{
        type: "properties",
        title: "Selected Slave",
        items: [
          %{label: "Name", value: selected.value},
          %{label: "Station", value: hex(selected.station, 4)},
          %{label: "Vendor", value: hex(selected.vendor_id, 8)},
          %{label: "Product", value: hex(selected.product_code, 8)},
          %{label: "Revision", value: hex(selected.revision, 8)},
          %{label: "AL state", value: inspect(selected.al_state)},
          %{label: "CoE", value: yes_no(selected.coe)}
        ]
      },
      %{
        type: "properties",
        title: "What We Know",
        items: [
          %{
            label: "Profile",
            value: inspect(Keyword.get(definition_options, :profile, :unknown))
          },
          %{label: "Mailbox supported", value: yes_no(mailbox_enabled?(mailbox_config))},
          %{label: "Sync managers", value: Integer.to_string(length(sm_configs))},
          %{label: "PDO entries", value: Integer.to_string(length(pdo_configs))},
          %{label: "Signals", value: Integer.to_string(length(signal_entries))},
          %{label: "Captured SDOs", value: Integer.to_string(length(Map.get(capture, :sdos, [])))}
        ]
      },
      mailbox_section(mailbox_config),
      sync_manager_section(sm_configs),
      %{
        type: "table",
        title: "PDO Layout",
        headers: ["Direction", "PDO", "SM", "Bits", "Bit offset"],
        rows:
          Enum.map(pdo_configs, fn pdo ->
            [
              Atom.to_string(pdo.direction),
              hex(pdo.index, 4),
              Integer.to_string(pdo.sm_index),
              Integer.to_string(pdo.bit_size),
              Integer.to_string(pdo.bit_offset)
            ]
          end)
      },
      %{
        type: "table",
        title: "Signal Names",
        headers: ["Direction", "PDO", "Bits", "Default", "Current"],
        rows:
          Enum.map(signal_entries, fn entry ->
            [
              entry.direction,
              hex(entry.pdo_index, 4),
              Integer.to_string(entry.bit_size),
              entry.default_name,
              entry.name
            ]
          end)
      },
      warnings_section(warnings)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp capture_inventory_section([]) do
    %{
      type: "message",
      title: "Discovered Slaves",
      tone: "info",
      text: "No slaves discovered yet. Scan the bus to start a temporary PREOP capture session."
    }
  end

  defp capture_inventory_section(inventory) do
    %{
      type: "table",
      title: "Discovered Slaves",
      headers: ["Name", "Station", "Vendor", "Product", "AL state", "CoE"],
      rows:
        Enum.map(inventory, fn slave ->
          [
            slave.value,
            hex(slave.station, 4),
            hex(slave.vendor_id, 8),
            hex(slave.product_code, 8),
            inspect(slave.al_state),
            yes_no(slave.coe)
          ]
        end)
    }
  end

  defp warnings_section([]), do: nil

  defp warnings_section(warnings) do
    %{
      type: "list",
      title: "Warnings",
      items: Enum.map(warnings, &to_string/1)
    }
  end

  defp capture_session_section(assigns) do
    %{
      type: "properties",
      title: "Capture Session",
      items:
        [
          %{label: "Transport", value: SetupTransport.summary_label(capture_transport(assigns))},
          %{label: "Master state", value: inspect(assigns.capture_master_state)},
          %{label: "Scan status", value: Atom.to_string(assigns.capture_scan_status)}
        ] ++ maybe_capture_error_item(assigns.capture_error)
    }
  end

  defp maybe_capture_error_item(nil), do: []
  defp maybe_capture_error_item(""), do: []
  defp maybe_capture_error_item(error), do: [%{label: "Last error", value: error}]

  defp mailbox_section(mailbox_config) do
    %{
      type: "properties",
      title: "Mailbox",
      items: [
        %{label: "Receive offset", value: hex(Map.get(mailbox_config, :recv_offset), 4)},
        %{
          label: "Receive size",
          value: Integer.to_string(Map.get(mailbox_config, :recv_size, 0))
        },
        %{label: "Send offset", value: hex(Map.get(mailbox_config, :send_offset), 4)},
        %{label: "Send size", value: Integer.to_string(Map.get(mailbox_config, :send_size, 0))}
      ]
    }
  end

  defp sync_manager_section([]), do: nil

  defp sync_manager_section(sm_configs) do
    %{
      type: "table",
      title: "Sync Managers",
      headers: ["SM", "Start", "Length", "Control"],
      rows:
        Enum.map(sm_configs, fn sm ->
          [
            Integer.to_string(sm.index),
            hex(sm.phys_start, 4),
            Integer.to_string(sm.length),
            hex(sm.ctrl, 8)
          ]
        end)
    }
  end

  defp normalize_capture_signal_names(attrs) when is_map(attrs) do
    base =
      attrs
      |> Map.get("signal_names", %{})
      |> case do
        map when is_map(map) ->
          Enum.into(map, %{}, fn {key, value} ->
            {to_string(key), normalize_capture_signal_name(value)}
          end)

        _ ->
          %{}
      end

    dynamic =
      Enum.reduce(attrs, %{}, fn
        {<<"capture_signal_name::", key::binary>>, value}, acc ->
          Map.put(acc, key, normalize_capture_signal_name(value))

        _, acc ->
          acc
      end)

    Map.merge(base, dynamic)
  end

  defp normalize_capture_signal_name(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> ""
      trimmed -> trimmed
    end
  end

  defp normalize_capture_signal_name(_value), do: ""

  defp resolved_capture_signal_name(signal_names, key, default_name) do
    case Map.get(signal_names, key) do
      value when is_binary(value) and value != "" -> value
      _ -> default_name
    end
  end

  defp parse_capture_sdos(value) when is_binary(value) do
    value
    |> String.split(~r/[\n,;]+/, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.reduce([], fn line, acc ->
      case parse_capture_sdo(line) do
        {:ok, ref} -> acc ++ [ref]
        :error -> acc
      end
    end)
  end

  defp parse_capture_sdos(_value), do: []

  defp encode_capture_snapshot(capture) when is_map(capture) do
    capture
    |> :erlang.term_to_binary(compressed: 6)
    |> Base.encode64(padding: false)
  end

  defp parse_capture_sdo(line) do
    case Regex.run(~r/^(.+?)(?::|\s+)(.+)$/, line, capture: :all_but_first) do
      [index, subindex] ->
        with {:ok, index} <- parse_non_neg_integer(index),
             {:ok, subindex} <- parse_non_neg_integer(subindex) do
          {:ok, {index, subindex}}
        end

      _ ->
        :error
    end
  end

  defp parse_non_neg_integer(value) when is_binary(value) do
    trimmed = String.trim(value)

    cond do
      trimmed == "" ->
        :error

      String.starts_with?(String.downcase(trimmed), "0x") ->
        case Integer.parse(String.slice(trimmed, 2..-1//1), 16) do
          {integer, ""} when integer >= 0 -> {:ok, integer}
          _ -> :error
        end

      true ->
        case Integer.parse(trimmed) do
          {integer, ""} when integer >= 0 -> {:ok, integer}
          _ -> :error
        end
    end
  end

  defp parse_non_neg_integer(_value), do: :error

  defp mailbox_enabled?(mailbox_config) when is_map(mailbox_config) do
    Map.get(mailbox_config, :write_size, 0) > 0 or Map.get(mailbox_config, :read_size, 0) > 0
  end

  defp mailbox_enabled?(_mailbox_config), do: false

  defp yes_no(true), do: "yes"
  defp yes_no(false), do: "no"
  defp yes_no(_value), do: "no"

  defp hex(nil, _pad), do: "n/a"

  defp hex(value, pad) when is_integer(value) and value >= 0 do
    "0x" <> String.upcase(String.pad_leading(Integer.to_string(value, 16), pad, "0"))
  end

  defp hex(_value, _pad), do: "n/a"

  defp should_auto_scan?(attrs, %{
         surface: "capture",
         capture_inventory: inventory,
         capture_master_state: state
       })
       when is_map(attrs) do
    map_size(attrs) == 0 and inventory == [] and state in [:idle, :not_started]
  end

  defp should_auto_scan?(_attrs, _assigns), do: false

  defp begin_capture_scan(ctx) do
    server = self()
    transport = ctx.assigns |> capture_transport() |> SetupTransport.refresh_auto()

    Task.start(fn ->
      send(server, {:capture_scan_complete, run_capture_scan(transport)})
    end)

    ctx =
      assign(ctx,
        transport_mode: transport.transport_mode,
        transport: transport.transport,
        interface: transport.interface,
        backup_interface: transport.backup_interface,
        host: transport.host,
        port: transport.port,
        capture_scan_status: :scanning,
        capture_error: nil
      )

    broadcast_event(ctx, "snapshot", payload(ctx.assigns))
    ctx
  end

  defp run_capture_scan(transport) do
    case capture_master_state() do
      state when state in [:preop_ready, :operational, :deactivated, :recovering, :activating] ->
        case Capture.list_slaves() do
          {:ok, _slaves} -> :ok
          {:error, reason} -> {:error, reason}
        end

      _ ->
        with {:ok, start_opts} <- SetupTransport.runtime_start_opts(transport),
             :ok <- restart_capture_master(capture_start_opts(start_opts)),
             :ok <- EtherCAT.await_running(@scan_await_timeout_ms),
             {:ok, _slaves} <- Capture.list_slaves() do
          :ok
        end
    end
  end

  defp capture_start_opts(start_opts) when is_list(start_opts) do
    start_opts
    |> Setup.scan_start_opts()
    |> Keyword.put(:dc, nil)
    |> Keyword.put(:domains, [])
    |> Keyword.put(:slaves, [])
  end

  defp restart_capture_master(start_opts) when is_list(start_opts) do
    _ = EtherCAT.stop()

    case EtherCAT.start(start_opts) do
      :ok -> :ok
      {:error, :already_started} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp refresh_capture_context(ctx, error) do
    assigns = normalized_assigns(to_attrs(ctx))

    ctx =
      assign(
        ctx,
        Keyword.merge(
          Keyword.new(assigns),
          capture_scan_status: if(error, do: :error, else: :ready),
          capture_error: error,
          inspection_sections: ctx.assigns.inspection_sections
        )
      )

    broadcast_event(ctx, "snapshot", payload(ctx.assigns))
    {:noreply, ctx}
  end

  defp refresh_capture_preview(ctx) do
    preview =
      build_capture_preview(
        ctx.assigns.surface,
        ctx.assigns.slave,
        ctx.assigns.capture_inventory,
        ctx.assigns.capture_sdos,
        ctx.assigns.signal_names
      )

    assign(ctx,
      capture_sections: preview.sections,
      capture_signal_entries: preview.signal_entries,
      signal_names: preview.signal_names,
      capture_snapshot: preview.snapshot
    )
  end

  defp run_inspection(ctx, runner) do
    attrs = to_attrs(ctx)

    next_sections =
      case runner.(attrs) do
        {:ok, sections} ->
          sections

        {:error, reason} ->
          [%{type: "message", title: "Live Inspection", tone: "error", text: inspect(reason)}]
      end

    ctx = assign(ctx, inspection_sections: next_sections)
    broadcast_event(ctx, "snapshot", payload(ctx.assigns))
    ctx
  end

  defp capture_transport(assigns) do
    %{
      transport_mode: Map.get(assigns, :transport_mode, :auto),
      transport: Map.get(assigns, :transport, :raw),
      interface: Map.get(assigns, :interface, "eth0"),
      backup_interface: Map.get(assigns, :backup_interface, "eth1"),
      host: Map.get(assigns, :host, "127.0.0.2"),
      port: Map.get(assigns, :port, 0x88A4)
    }
  end
end
