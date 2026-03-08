defmodule KinoEtherCAT.SmartCells.SDOExplorer do
  use Kino.JS, assets_path: "lib/assets/explorer_cell/build"
  use Kino.JS.Live
  use Kino.SmartCell, name: "EtherCAT SDO Explorer"

  alias KinoEtherCAT.SmartCells.{ExplorerSource, ExplorerSupport}

  @impl true
  def init(attrs, ctx) do
    suggestions = ExplorerSupport.slave_suggestions(:coe)

    {:ok,
     assign(ctx,
       slave: ExplorerSupport.normalize_selected_slave(attrs["slave"], suggestions),
       operation: attrs["operation"] || "upload",
       index: attrs["index"] || "0x1018",
       subindex: attrs["subindex"] || "0x00",
       write_data: attrs["write_data"] || "",
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
        index: Map.get(params, "index", ctx.assigns.index),
        subindex: Map.get(params, "subindex", ctx.assigns.subindex),
        write_data: Map.get(params, "write_data", ctx.assigns.write_data)
      )

    broadcast_event(ctx, "snapshot", payload(ctx.assigns))
    {:noreply, ctx}
  end

  def handle_event("refresh_slaves", _params, ctx) do
    suggestions = ExplorerSupport.slave_suggestions(:coe)

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
      "index" => ctx.assigns.index,
      "subindex" => ctx.assigns.subindex,
      "write_data" => ctx.assigns.write_data
    }
  end

  @impl true
  def to_source(attrs) do
    ExplorerSource.render_sdo(attrs)
  end

  defp payload(assigns) do
    %{
      title: "CoE SDO",
      description: "Generate a repeatable mailbox upload or download against the running bus.",
      actions: [%{id: "refresh_slaves", label: "Refresh bus"}],
      values: %{
        "slave" => assigns.slave,
        "operation" => assigns.operation,
        "index" => assigns.index,
        "subindex" => assigns.subindex,
        "write_data" => assigns.write_data
      },
      fields:
        [
          ExplorerSupport.slave_field(
            "Slave",
            assigns.suggestions,
            "Select a CoE-capable slave on the active master."
          ),
          %{
            name: "operation",
            label: "Operation",
            type: "select",
            options: [
              %{value: "upload", label: "Upload"},
              %{value: "download", label: "Download"}
            ]
          },
          %{
            name: "index",
            label: "Index",
            type: "text",
            placeholder: "0x1018",
            help: "Use decimal or 0x-prefixed hexadecimal."
          },
          %{
            name: "subindex",
            label: "Subindex",
            type: "text",
            placeholder: "0x00"
          }
        ] ++ maybe_download_field(assigns.operation)
    }
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
end
