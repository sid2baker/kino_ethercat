defmodule KinoEtherCAT.VisualizerCell do
  use Kino.JS, assets_path: "lib/assets/visualizer_cell/build"
  use Kino.JS.Live
  use Kino.SmartCell, name: "EtherCAT Visualizer"

  @impl true
  def init(attrs, ctx) do
    selected = attrs["selected"] || []
    {status, selected} = if selected == [], do: fetch_slaves(), else: {:ok, selected}

    {:ok, assign(ctx, selected: selected, status: status)}
  end

  @impl true
  def handle_connect(ctx) do
    {:ok,
     %{
       selected: ctx.assigns.selected,
       status: to_string(ctx.assigns.status)
     }, ctx}
  end

  @impl true
  def handle_event("refresh", _params, ctx) do
    {status, selected} = fetch_slaves()
    broadcast_event(ctx, "refreshed", %{selected: selected, status: to_string(status)})
    {:noreply, assign(ctx, selected: selected, status: status)}
  end

  def handle_event("reorder", %{"names" => names}, ctx) do
    by_name = Map.new(ctx.assigns.selected, &{&1["name"], &1})
    selected = Enum.flat_map(names, fn name -> Map.get(by_name, name, []) |> List.wrap() end)
    {:noreply, assign(ctx, selected: selected)}
  end

  def handle_event("remove", %{"name" => name}, ctx) do
    selected = Enum.reject(ctx.assigns.selected, &(&1["name"] == name))
    {:noreply, assign(ctx, selected: selected)}
  end

  def handle_event("update_opts", %{"name" => name, "columns" => columns}, ctx) do
    selected =
      Enum.map(ctx.assigns.selected, fn entry ->
        if entry["name"] == name, do: Map.put(entry, "columns", columns), else: entry
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
      Enum.map(selected, fn %{"name" => name, "columns" => columns} ->
        name_atom = String.to_atom(name)

        if columns do
          quote do
            KinoEtherCAT.render(unquote(name_atom), columns: unquote(columns))
            |> Kino.render()
          end
        else
          quote do
            KinoEtherCAT.render(unquote(name_atom)) |> Kino.render()
          end
        end
      end)

    ast = {:__block__, [], render_asts ++ [quote(do: Kino.nothing())]}
    Kino.SmartCell.quoted_to_string(ast)
  end

  defp fetch_slaves do
    slaves = EtherCAT.slaves()
    entries = Enum.map(slaves, &%{"name" => to_string(&1.name), "columns" => nil})
    {:ok, entries}
  rescue
    _ -> {:not_running, []}
  end
end
