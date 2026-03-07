defmodule KinoEtherCAT.VisualizerCell do
  use Kino.JS, assets_path: "lib/assets/visualizer_cell/build"
  use Kino.JS.Live
  use Kino.SmartCell, name: "EtherCAT Visualizer"

  @impl true
  def init(attrs, ctx) do
    selected = attrs["selected"] || []
    {status, available} = fetch_slaves()

    {:ok,
     assign(ctx,
       available: available,
       selected: selected,
       status: status
     )}
  end

  @impl true
  def handle_connect(ctx) do
    {:ok,
     %{
       available: ctx.assigns.available,
       selected: ctx.assigns.selected,
       status: to_string(ctx.assigns.status)
     }, ctx}
  end

  @impl true
  def handle_event("refresh", _params, ctx) do
    {status, available} = fetch_slaves()
    broadcast_event(ctx, "refreshed", %{available: available, status: to_string(status)})
    {:noreply, assign(ctx, available: available, status: status)}
  end

  def handle_event("select", %{"name" => name}, ctx) do
    already = Enum.any?(ctx.assigns.selected, &(&1["name"] == name))

    if already do
      {:noreply, ctx}
    else
      entry = %{"name" => name, "layout" => "columns"}
      selected = ctx.assigns.selected ++ [entry]
      {:noreply, assign(ctx, selected: selected)}
    end
  end

  def handle_event("deselect", %{"name" => name}, ctx) do
    selected = Enum.reject(ctx.assigns.selected, &(&1["name"] == name))
    {:noreply, assign(ctx, selected: selected)}
  end

  def handle_event("update_opts", %{"name" => name, "layout" => layout}, ctx) do
    selected =
      Enum.map(ctx.assigns.selected, fn entry ->
        if entry["name"] == name, do: Map.put(entry, "layout", layout), else: entry
      end)

    {:noreply, assign(ctx, selected: selected)}
  end

  @impl true
  def to_attrs(ctx) do
    %{"selected" => ctx.assigns.selected}
  end

  @impl true
  def to_source(%{"selected" => []}) do
    ""
  end

  def to_source(%{"selected" => selected}) do
    render_asts =
      Enum.map(selected, fn %{"name" => name, "layout" => layout} ->
        name_atom = String.to_atom(name)
        layout_atom = String.to_atom(layout)

        quote do
          KinoEtherCAT.render(unquote(name_atom),
            layout: unquote(layout_atom),
            on_error: :placeholder
          )
          |> Kino.render()
        end
      end)

    ast = {:__block__, [], render_asts ++ [quote(do: Kino.nothing())]}
    Kino.SmartCell.quoted_to_string(ast)
  end

  defp fetch_slaves do
    slaves = EtherCAT.slaves()
    names = Enum.map(slaves, &to_string(&1.name))
    {:ok, names}
  rescue
    _ -> {:not_running, []}
  end
end
