defmodule KinoEtherCAT.SIIExplorer do
  use Kino.JS, assets_path: "lib/assets/explorer_cell/build"
  use Kino.JS.Live
  use Kino.SmartCell, name: "EtherCAT SII Explorer"

  alias KinoEtherCAT.{ExplorerSource, ExplorerSupport}

  @operations [
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
    suggestions = ExplorerSupport.slave_suggestions(:all)

    {:ok,
     assign(ctx,
       slave: ExplorerSupport.normalize_selected_slave(attrs["slave"], suggestions),
       operation: attrs["operation"] || "identity",
       word_address: attrs["word_address"] || "0x0040",
       word_count: attrs["word_count"] || "8",
       write_data: attrs["write_data"] || "00 00",
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
        word_address: Map.get(params, "word_address", ctx.assigns.word_address),
        word_count: Map.get(params, "word_count", ctx.assigns.word_count),
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
      "word_address" => ctx.assigns.word_address,
      "word_count" => ctx.assigns.word_count,
      "write_data" => ctx.assigns.write_data
    }
  end

  @impl true
  def to_source(attrs) do
    ExplorerSource.render_sii(attrs)
  end

  defp payload(assigns) do
    %{
      title: "SII EEPROM",
      description: "Generate EEPROM and ESC reload calls against the selected slave station.",
      actions: [%{id: "refresh_slaves", label: "Refresh bus"}],
      values: %{
        "slave" => assigns.slave,
        "operation" => assigns.operation,
        "word_address" => assigns.word_address,
        "word_count" => assigns.word_count,
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
          %{name: "operation", label: "Operation", type: "select", options: @operations}
        ] ++ maybe_word_fields(assigns.operation)
    }
  end

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
end
