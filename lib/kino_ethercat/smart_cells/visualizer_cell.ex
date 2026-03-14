defmodule KinoEtherCAT.SmartCells.Visualizer do
  use Kino.JS, assets_path: "lib/assets/visualizer_cell/build"
  use Kino.JS.Live
  use Kino.SmartCell, name: "EtherCAT Visualizer"

  alias Kino.JS.Live.Context
  alias KinoEtherCAT.SmartCells.Source

  @refresh_interval_ms 2_000
  @max_seeded_signals 4

  @impl true
  def init(attrs, ctx) do
    {status, available} = fetch_signals()
    auto_seed_selection? = not Map.has_key?(attrs, "selected")
    selected = normalize_selected(attrs["selected"], available, auto_seed_selection?)
    schedule_refresh()

    {:ok,
     Context.assign(ctx,
       selected: selected,
       available: available,
       status: status,
       auto_seed_selection?: auto_seed_selection?
     )}
  end

  @impl true
  def handle_connect(ctx) do
    {:ok, payload(ctx.assigns), ctx}
  end

  @impl true
  def handle_event("add", %{"key" => key}, ctx) do
    selected = append_selected(ctx.assigns.selected, key, ctx.assigns.available)
    ctx = Context.assign(ctx, selected: selected, auto_seed_selection?: false)
    {:noreply, broadcast_snapshot(ctx)}
  end

  def handle_event("reorder", %{"keys" => keys}, ctx) do
    selected = reorder_selected(ctx.assigns.selected, keys)
    ctx = Context.assign(ctx, selected: selected, auto_seed_selection?: false)
    {:noreply, broadcast_snapshot(ctx)}
  end

  def handle_event("remove", %{"key" => key}, ctx) do
    selected = Enum.reject(ctx.assigns.selected, &(&1["key"] == key))
    ctx = Context.assign(ctx, selected: selected, auto_seed_selection?: false)
    {:noreply, broadcast_snapshot(ctx)}
  end

  @impl true
  def handle_info(:refresh_inventory, ctx) do
    schedule_refresh()
    {status, available} = fetch_signals()

    selected =
      normalize_selected(ctx.assigns.selected, available, ctx.assigns.auto_seed_selection?)

    ctx =
      Context.assign(ctx,
        status: status,
        available: available,
        selected: selected
      )

    {:noreply, broadcast_snapshot(ctx)}
  end

  @impl true
  def to_attrs(ctx) do
    %{"selected" => ctx.assigns.selected}
  end

  @impl true
  def to_source(attrs) when is_map(attrs) do
    selected = Map.get(attrs, "selected", [])

    widgets =
      selected
      |> normalize_selected([], false)
      |> Enum.map(&widget_source/1)
      |> Enum.reject(&is_nil/1)

    case widgets do
      [] ->
        ""

      _ ->
        """
        widgets = [
        #{Enum.map_join(widgets, ",\n", &("  " <> &1))}
        ]

        case widgets do
          [] -> Kino.nothing()
          [widget] -> widget
          _ -> Kino.Layout.grid(widgets, columns: #{widget_columns(length(widgets))})
        end
        |> Kino.render()

        Kino.nothing()
        """
        |> Source.format()
    end
  end

  defp payload(assigns) do
    available_by_key = Map.new(assigns.available, &{&1["key"], &1})
    selected = Enum.map(assigns.selected, &decorate_entry(&1, available_by_key))
    selected_keys = MapSet.new(Enum.map(selected, & &1.key))

    available =
      assigns.available
      |> Enum.reject(&MapSet.member?(selected_keys, &1["key"]))
      |> Enum.map(&decorate_entry(&1, available_by_key))

    %{
      title: "Signal visualizer",
      status: to_string(assigns.status),
      selected: selected,
      available: available
    }
  end

  defp fetch_signals do
    case EtherCAT.slaves() do
      {:ok, slaves} when is_list(slaves) ->
        signals =
          slaves
          |> Enum.with_index()
          |> Enum.flat_map(fn {slave, slave_index} ->
            slave_signal_entries(slave, slave_index)
          end)
          |> Enum.sort_by(&signal_sort_key/1)

        {:ok, signals}

      _ ->
        {:not_running, []}
    end
  rescue
    _ -> {:not_running, []}
  end

  defp slave_signal_entries(%{name: name}, slave_index) when is_atom(name) do
    case safe(fn -> EtherCAT.slave_info(name) end, {:error, :not_found}) do
      {:ok, info} ->
        info
        |> Map.get(:signals, [])
        |> Enum.with_index()
        |> Enum.map(fn {signal, signal_index} ->
          signal_entry(name, slave_index, signal, signal_index)
        end)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  defp slave_signal_entries(_slave, _slave_index), do: []

  defp signal_entry(slave_name, slave_index, %{} = signal, signal_index) do
    direction = normalize_direction(Map.get(signal, :direction))
    bit_size = normalize_bit_size(Map.get(signal, :bit_size))
    signal_name = signal_name(signal)
    default_widget = default_widget(direction, bit_size)

    if is_binary(signal_name) and signal_name != "" and not is_nil(default_widget) do
      %{
        "key" => signal_key(slave_name, signal_name),
        "slave" => Atom.to_string(slave_name),
        "signal" => signal_name,
        "direction" => direction,
        "bit_size" => bit_size,
        "domain" => normalize_domain(Map.get(signal, :domain)),
        "slave_index" => slave_index,
        "signal_index" => signal_index,
        "default_widget" => default_widget,
        "widget" => "auto",
        "label" => nil
      }
    end
  end

  defp signal_entry(_slave_name, _slave_index, _signal, _signal_index), do: nil

  defp schedule_refresh, do: Process.send_after(self(), :refresh_inventory, @refresh_interval_ms)

  defp broadcast_snapshot(ctx) do
    Context.broadcast_event(ctx, "snapshot", payload(ctx.assigns))
    ctx
  end

  defp normalize_selected(selected, available, seed_selection?)
       when is_list(available) and is_boolean(seed_selection?) do
    available_by_key = Map.new(available, &{&1["key"], &1})
    available_by_slave = Enum.group_by(available, & &1["slave"])

    selected =
      selected
      |> List.wrap()
      |> Enum.flat_map(&normalize_selected_entry(&1, available_by_key, available_by_slave))
      |> Enum.uniq_by(& &1["key"])

    cond do
      selected != [] ->
        selected

      seed_selection? and available != [] ->
        seed_selection(available)

      true ->
        []
    end
  end

  defp normalize_selected_entry(
         %{"slave" => _slave, "signal" => _signal} = entry,
         available_by_key,
         _by_slave
       ) do
    case normalize_signal_selection(entry) do
      nil ->
        []

      normalized ->
        [merge_available_entry(normalized, Map.get(available_by_key, normalized["key"]))]
    end
  end

  defp normalize_selected_entry(%{"name" => slave_name}, _available_by_key, available_by_slave)
       when is_binary(slave_name) do
    slave_name
    |> String.trim()
    |> then(&Map.get(available_by_slave, &1, []))
    |> Enum.map(&selection_from_available/1)
  end

  defp normalize_selected_entry(slave_name, _available_by_key, available_by_slave)
       when is_binary(slave_name) do
    normalize_selected_entry(%{"name" => slave_name}, %{}, available_by_slave)
  end

  defp normalize_selected_entry(_entry, _available_by_key, _by_slave), do: []

  defp normalize_signal_selection(%{} = entry) do
    slave = normalize_name(Map.get(entry, "slave"))
    signal = normalize_name(Map.get(entry, "signal"))

    if is_binary(slave) and is_binary(signal) do
      normalized = %{
        "key" => signal_key(slave, signal),
        "slave" => slave,
        "signal" => signal,
        "direction" => normalize_direction(Map.get(entry, "direction")),
        "bit_size" => normalize_bit_size(Map.get(entry, "bit_size")),
        "domain" => normalize_domain(Map.get(entry, "domain")),
        "slave_index" => normalize_index(Map.get(entry, "slave_index")),
        "signal_index" => normalize_index(Map.get(entry, "signal_index")),
        "default_widget" => normalize_widget_name(Map.get(entry, "default_widget")),
        "widget" => Map.get(entry, "widget"),
        "label" => normalize_label(Map.get(entry, "label"))
      }

      normalized
      |> ensure_default_widget()
      |> then(fn value ->
        Map.put(value, "widget", normalize_widget(Map.get(value, "widget"), value))
      end)
    end
  end

  defp normalize_signal_selection(_entry), do: nil

  defp merge_available_entry(selection, nil) do
    selection
    |> ensure_default_widget()
    |> then(fn value ->
      Map.put(value, "widget", normalize_widget(Map.get(value, "widget"), value))
    end)
  end

  defp merge_available_entry(selection, available) do
    selection
    |> Map.merge(
      Map.take(available, [
        "slave",
        "signal",
        "direction",
        "bit_size",
        "domain",
        "slave_index",
        "signal_index",
        "default_widget"
      ])
    )
    |> Map.put("key", available["key"])
    |> then(fn value ->
      Map.put(value, "widget", normalize_widget(Map.get(selection, "widget"), value))
    end)
  end

  defp selection_from_available(available) do
    available
    |> Map.take([
      "key",
      "slave",
      "signal",
      "direction",
      "bit_size",
      "domain",
      "slave_index",
      "signal_index",
      "default_widget"
    ])
    |> Map.put("widget", "auto")
    |> Map.put("label", nil)
  end

  defp seed_selection(available) do
    preferred =
      [
        Enum.find(available, &(&1["direction"] == "output" and &1["signal"] == "ch1")),
        Enum.find(available, &(&1["direction"] == "input" and &1["signal"] == "ch1"))
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq_by(& &1["key"])
      |> Enum.map(&selection_from_available/1)

    case preferred do
      [] ->
        available
        |> Enum.take(@max_seeded_signals)
        |> Enum.map(&selection_from_available/1)

      entries ->
        entries
    end
  end

  defp append_selected(selected, key, available) when is_binary(key) do
    if Enum.any?(selected, &(&1["key"] == key)) do
      selected
    else
      case Enum.find(available, &(&1["key"] == key)) do
        nil -> selected
        entry -> selected ++ [selection_from_available(entry)]
      end
    end
  end

  defp reorder_selected(selected, keys) when is_list(keys) do
    by_key = Map.new(selected, &{&1["key"], &1})
    ordered = Enum.flat_map(keys, fn key -> Map.get(by_key, key, []) |> List.wrap() end)
    key_set = MapSet.new(keys)
    remaining = Enum.reject(selected, &MapSet.member?(key_set, &1["key"]))
    ordered ++ remaining
  end

  defp decorate_entry(entry, available_by_key) do
    available? = Map.has_key?(available_by_key, entry["key"])
    resolved_widget = resolve_widget(entry)

    %{
      key: entry["key"],
      slave: entry["slave"],
      slave_index: entry["slave_index"],
      signal: entry["signal"],
      signal_index: entry["signal_index"],
      direction: entry["direction"],
      bit_size: entry["bit_size"],
      domain: entry["domain"],
      resolved_widget: resolved_widget,
      widget_label: widget_label(resolved_widget),
      available: available?
    }
  end

  defp supported_widgets(entry) do
    case {entry["direction"], entry["bit_size"]} do
      {"output", 1} ->
        [{"Switch", "switch"}]

      {"input", 1} ->
        [{"LED", "led"}, {"Value", "value"}]

      {"input", bit_size} when is_integer(bit_size) and bit_size > 1 ->
        [{"Value", "value"}]

      _ ->
        []
    end
  end

  defp resolve_widget(entry) do
    default =
      Map.get(entry, "default_widget") || default_widget(entry["direction"], entry["bit_size"])

    supported = Enum.map(supported_widgets(entry), &elem(&1, 1))

    case normalize_widget_name(Map.get(entry, "widget")) do
      "auto" ->
        default

      widget when is_binary(widget) ->
        if widget in supported, do: widget, else: default

      _ ->
        default
    end
  end

  defp widget_source(entry) do
    case resolve_widget(entry) do
      nil ->
        nil

      widget ->
        label =
          case normalize_label(Map.get(entry, "label")) do
            nil -> ""
            value -> ", label: #{inspect(value)}"
          end

        "KinoEtherCAT.Widgets.#{widget}(#{Source.atom_literal(entry["slave"])}, #{Source.atom_literal(entry["signal"])}#{label})"
    end
  end

  defp signal_sort_key(entry) do
    {
      entry["slave_index"] || 9_999,
      natural_signal_key(entry["signal"]),
      entry["signal_index"] || 9_999,
      direction_rank(entry["direction"]),
      String.downcase(entry["slave"] || "")
    }
  end

  defp signal_key(slave_name, signal_name) when is_atom(slave_name),
    do: signal_key(Atom.to_string(slave_name), signal_name)

  defp signal_key(slave_name, signal_name) when is_binary(slave_name) and is_binary(signal_name),
    do: "#{slave_name}.#{signal_name}"

  defp signal_name(%{name: name}) when is_atom(name), do: Atom.to_string(name)
  defp signal_name(%{name: name}) when is_binary(name), do: String.trim(name)
  defp signal_name(_signal), do: nil

  defp ensure_default_widget(entry) do
    Map.put(
      entry,
      "default_widget",
      Map.get(entry, "default_widget") || default_widget(entry["direction"], entry["bit_size"])
    )
  end

  defp default_widget("output", 1), do: "switch"
  defp default_widget("input", 1), do: "led"
  defp default_widget("input", bit_size) when is_integer(bit_size) and bit_size > 1, do: "value"
  defp default_widget(_direction, _bit_size), do: nil

  defp normalize_widget(widget, entry) do
    supported = Enum.map(supported_widgets(entry), &elem(&1, 1))

    case normalize_widget_name(widget) do
      nil -> "auto"
      "auto" -> "auto"
      value -> if(value in supported, do: value, else: "auto")
    end
  end

  defp normalize_widget_name(value) when is_binary(value) do
    case String.trim(value) do
      "auto" -> "auto"
      "led" -> "led"
      "switch" -> "switch"
      "value" -> "value"
      _ -> nil
    end
  end

  defp normalize_widget_name(_value), do: nil

  defp normalize_label(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_label(_value), do: nil

  defp normalize_name(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_name(_value), do: nil

  defp normalize_direction(value) when value in [:input, :output], do: Atom.to_string(value)
  defp normalize_direction(value) when value in ["input", "output"], do: value
  defp normalize_direction(_value), do: nil

  defp normalize_domain(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_domain(value) when is_binary(value) and value != "", do: String.trim(value)
  defp normalize_domain(_value), do: nil

  defp normalize_bit_size(value) when is_integer(value) and value > 0, do: value

  defp normalize_bit_size(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> nil
    end
  end

  defp normalize_bit_size(_value), do: nil

  defp normalize_index(value) when is_integer(value) and value >= 0, do: value

  defp normalize_index(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed >= 0 -> parsed
      _ -> nil
    end
  end

  defp normalize_index(_value), do: nil

  defp direction_rank("output"), do: 0
  defp direction_rank("input"), do: 1
  defp direction_rank(_direction), do: 2

  defp widget_label("switch"), do: "output"
  defp widget_label("led"), do: "input"
  defp widget_label("value"), do: "value"
  defp widget_label(_widget), do: "signal"

  defp natural_signal_key(name) when is_binary(name) do
    case Regex.run(~r/^(.*?)(\d+)$/, name, capture: :all_but_first) do
      [prefix, digits] -> {prefix, String.length(digits), String.to_integer(digits), name}
      _ -> {name, 0, 0, name}
    end
  end

  defp widget_columns(count) when count <= 4, do: 2
  defp widget_columns(count) when count <= 9, do: 3
  defp widget_columns(_count), do: 4

  defp safe(fun, default) do
    fun.()
  rescue
    _ -> default
  catch
    :exit, _ -> default
  end
end
