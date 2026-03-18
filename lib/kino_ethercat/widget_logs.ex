defmodule KinoEtherCAT.WidgetLogs do
  @moduledoc false

  use GenServer
  require Logger

  alias EtherCAT.{Domain, Master, Slave}

  @handler_id :kino_ethercat_widget_logs
  @default_filter_id :kino_ethercat_widget_logs
  @max_entries 200
  @default_level :all
  @log_levels [
    :debug,
    :info,
    :notice,
    :warning,
    :error,
    :critical,
    :alert,
    :emergency,
    :none,
    :all
  ]

  @type scope :: :master | :bus | :dc | {:slave, atom()} | {:domain, atom()}
  @type log_level ::
          :debug
          | :info
          | :notice
          | :warning
          | :error
          | :critical
          | :alert
          | :emergency
          | :none
          | :all
  @type entry :: %{
          id: integer(),
          at_ms: integer(),
          level: String.t(),
          text: String.t()
        }

  defmodule Handler do
    @moduledoc false

    @behaviour :logger_handler

    @impl true
    def log(event, _config) do
      KinoEtherCAT.WidgetLogs.record(event)
    end
  end

  defmodule DefaultFilter do
    @moduledoc false

    def filter(event, _opts) do
      if KinoEtherCAT.WidgetLogs.silence?(event) do
        :stop
      else
        :ignore
      end
    end
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec subscribe(pid(), struct() | scope()) :: :ok
  def subscribe(pid, resource_or_scope) when is_pid(pid) do
    with {:ok, scope} <- scope(resource_or_scope),
         router when is_pid(router) <- Process.whereis(__MODULE__) do
      GenServer.call(router, {:subscribe, pid, scope})
    else
      _ -> :ok
    end
  catch
    :exit, _ -> :ok
  end

  @spec level(struct() | scope()) :: log_level()
  def level(resource_or_scope) do
    with {:ok, scope} <- scope(resource_or_scope),
         router when is_pid(router) <- Process.whereis(__MODULE__) do
      GenServer.call(router, {:level, scope})
    else
      _ -> @default_level
    end
  catch
    :exit, _ -> @default_level
  end

  @spec set_level(struct() | scope(), log_level()) ::
          :ok | {:error, :invalid_log_level | :invalid_scope}
  def set_level(resource_or_scope, level) when is_atom(level) do
    with {:ok, scope} <- scope(resource_or_scope),
         true <- valid_level?(level),
         router when is_pid(router) <- Process.whereis(__MODULE__) do
      GenServer.call(router, {:set_level, scope, level})
    else
      false -> {:error, :invalid_log_level}
      :error -> {:error, :invalid_scope}
      _ -> :ok
    end
  catch
    :exit, _ -> :ok
  end

  @spec clear(struct() | scope()) :: :ok | {:error, :invalid_scope}
  def clear(resource_or_scope) do
    with {:ok, scope} <- scope(resource_or_scope),
         router when is_pid(router) <- Process.whereis(__MODULE__) do
      GenServer.call(router, {:clear, scope})
    else
      :error -> {:error, :invalid_scope}
      _ -> :ok
    end
  catch
    :exit, _ -> :ok
  end

  @spec entries(struct() | scope()) :: [entry()]
  def entries(resource_or_scope) do
    with {:ok, scope} <- scope(resource_or_scope),
         router when is_pid(router) <- Process.whereis(__MODULE__) do
      GenServer.call(router, {:entries, scope})
    else
      _ -> []
    end
  catch
    :exit, _ -> []
  end

  @spec record(map()) :: :ok
  def record(event) when is_map(event) do
    case log_entry(event) do
      {scope, entry} ->
        case Process.whereis(__MODULE__) do
          pid when is_pid(pid) ->
            send(pid, {:append_entry, scope, entry})
            :ok

          _ ->
            :ok
        end

      nil ->
        :ok
    end
  end

  @spec silence?(map()) :: boolean()
  def silence?(event) when is_map(event) do
    case log_entry(event) do
      {_scope, _entry} -> true
      nil -> false
    end
  end

  @spec scope(struct() | scope()) :: {:ok, scope()} | :error
  def scope(%Master{}), do: {:ok, :master}
  def scope(%KinoEtherCAT.Runtime.BusResource{}), do: {:ok, :bus}
  def scope(%Slave{name: name}) when is_atom(name), do: {:ok, {:slave, name}}
  def scope(%Domain{id: id}) when is_atom(id), do: {:ok, {:domain, id}}
  def scope(resource) when is_struct(resource, EtherCAT.DC), do: {:ok, :dc}
  def scope(resource) when is_struct(resource, EtherCAT.DC.Status), do: {:ok, :dc}
  def scope(:master), do: {:ok, :master}
  def scope(:bus), do: {:ok, :bus}
  def scope(:dc), do: {:ok, :dc}
  def scope({:slave, name}) when is_atom(name), do: {:ok, {:slave, name}}
  def scope({:domain, id}) when is_atom(id), do: {:ok, {:domain, id}}
  def scope(_resource_or_scope), do: :error

  @impl true
  def init(_opts) do
    install_logger_integration()

    {:ok,
     %{
       entries: %{},
       levels: %{},
       subscribers: %{},
       monitors: %{}
     }}
  end

  @impl true
  def handle_call({:subscribe, pid, scope}, _from, state) do
    install_output_filters()

    monitors =
      case state.monitors do
        %{^pid => _ref} -> state.monitors
        monitors -> Map.put(monitors, pid, Process.monitor(pid))
      end

    subscribers =
      Map.update(state.subscribers, scope, MapSet.new([pid]), &MapSet.put(&1, pid))

    {:reply, :ok, %{state | subscribers: subscribers, monitors: monitors}}
  end

  def handle_call({:entries, scope}, _from, state) do
    {:reply, filtered_entries(state, scope), state}
  end

  def handle_call({:level, scope}, _from, state) do
    {:reply, current_level(state, scope), state}
  end

  def handle_call({:set_level, scope, level}, _from, state) do
    levels = Map.put(state.levels, scope, level)
    notify_subscribers(state.subscribers, scope)
    {:reply, :ok, %{state | levels: levels}}
  end

  def handle_call({:clear, scope}, _from, state) do
    entries = Map.delete(state.entries, scope)
    notify_subscribers(state.subscribers, scope)
    {:reply, :ok, %{state | entries: entries}}
  end

  @impl true
  def handle_info({:append_entry, scope, entry}, state) do
    entries =
      Map.update(state.entries, scope, [entry], fn current ->
        trim_entries(current ++ [entry])
      end)

    notify_subscribers(state.subscribers, scope)

    {:noreply, %{state | entries: entries}}
  end

  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    monitors =
      case state.monitors do
        %{^pid => ^ref} -> Map.delete(state.monitors, pid)
        monitors -> monitors
      end

    subscribers =
      Enum.reduce(state.subscribers, %{}, fn {scope, pids}, acc ->
        remaining = MapSet.delete(pids, pid)

        if MapSet.size(remaining) == 0 do
          acc
        else
          Map.put(acc, scope, remaining)
        end
      end)

    {:noreply, %{state | subscribers: subscribers, monitors: monitors}}
  end

  @impl true
  def terminate(_reason, _state) do
    remove_default_filter()
    remove_handler()
    :ok
  end

  defp install_logger_integration do
    install_handler()
    install_output_filters()
  end

  defp install_handler do
    if @handler_id in :logger.get_handler_ids() do
      :ok
    else
      case :logger.add_handler(@handler_id, Handler, %{}) do
        :ok -> :ok
        {:error, reason} -> raise "failed to install widget log handler: #{inspect(reason)}"
      end
    end
  end

  defp install_output_filters do
    :logger.get_handler_ids()
    |> Enum.reject(&(&1 == @handler_id))
    |> Enum.each(&install_handler_filter/1)
  end

  defp install_handler_filter(handler_id) do
    case :logger.get_handler_config(handler_id) do
      {:ok, config} ->
        filters = Map.get(config, :filters, [])

        if Enum.any?(filters, fn {id, _filter} -> id == @default_filter_id end) do
          :ok
        else
          case :logger.add_handler_filter(
                 handler_id,
                 @default_filter_id,
                 {&DefaultFilter.filter/2, nil}
               ) do
            :ok -> :ok
            {:error, {:not_found, ^handler_id}} -> :ok
            {:error, reason} -> raise "failed to install widget log filter: #{inspect(reason)}"
          end
        end

      _ ->
        :ok
    end
  end

  defp remove_default_filter do
    :logger.get_handler_ids()
    |> Enum.reject(&(&1 == @handler_id))
    |> Enum.each(fn handler_id ->
      case :logger.remove_handler_filter(handler_id, @default_filter_id) do
        :ok -> :ok
        {:error, _reason} -> :ok
      end
    end)
  end

  defp remove_handler do
    case :logger.remove_handler(@handler_id) do
      :ok -> :ok
      {:error, _reason} -> :ok
    end
  end

  defp notify_subscribers(subscribers, scope) do
    Enum.each(Map.get(subscribers, scope, MapSet.new()), fn pid ->
      send(pid, {:kino_ethercat, :logs_updated, scope})
    end)
  end

  defp filtered_entries(state, scope) do
    threshold = current_level(state, scope)

    state.entries
    |> Map.get(scope, [])
    |> Enum.filter(&visible_at_level?(&1, threshold))
  end

  defp current_level(state, scope) do
    Map.get(state.levels, scope, @default_level)
  end

  defp visible_at_level?(_entry, :all), do: true
  defp visible_at_level?(_entry, :none), do: false

  defp visible_at_level?(%{level: level}, threshold) when is_binary(level) do
    case parse_entry_level(level) do
      {:ok, entry_level} -> Logger.compare_levels(entry_level, threshold) != :lt
      :error -> true
    end
  end

  defp visible_at_level?(_entry, _threshold), do: true

  defp parse_entry_level(level) when is_binary(level) do
    level
    |> String.to_existing_atom()
    |> then(&{:ok, &1})
  rescue
    ArgumentError -> :error
  end

  defp valid_level?(level), do: level in @log_levels

  defp trim_entries(entries) when length(entries) > @max_entries do
    Enum.take(entries, -@max_entries)
  end

  defp trim_entries(entries), do: entries

  defp log_entry(%{level: level, meta: meta, msg: msg}) when is_map(meta) do
    with text when text != "" <- format_message(msg),
         scope when not is_nil(scope) <- scope_from_event(meta, text) do
      {scope,
       %{
         id: System.unique_integer([:positive, :monotonic]),
         at_ms: System.system_time(:millisecond),
         level: Atom.to_string(level),
         text: text
       }}
    else
      _ -> nil
    end
  end

  defp log_entry(_event), do: nil

  defp scope_from_event(meta, text) do
    pid_scope = scope_from_pid(Map.get(meta, :pid))

    case pid_scope do
      nil ->
        case scope_from_metadata(meta) do
          nil -> scope_from_message(text)
          scope -> scope
        end

      scope -> scope
    end
  end

  defp scope_from_pid(pid) when is_pid(pid) do
    case Process.info(pid, :registered_name) do
      {:registered_name, Master} -> :master
      {:registered_name, Bus} -> :bus
      {:registered_name, EtherCAT.DC} -> :dc
      _ -> scope_from_registry(pid)
    end
  rescue
    ArgumentError -> nil
  end

  defp scope_from_pid(_pid), do: nil

  defp scope_from_registry(pid) when is_pid(pid) do
    if Process.whereis(EtherCAT.Registry) do
      case Registry.keys(EtherCAT.Registry, pid) do
        [{:slave, name} | _rest] when is_atom(name) -> {:slave, name}
        [{:domain, id} | _rest] when is_atom(id) -> {:domain, id}
        _ -> nil
      end
    else
      nil
    end
  rescue
    _ -> nil
  end

  defp scope_from_registry(_pid), do: nil

  defp scope_from_metadata(%{component: :master}), do: :master
  defp scope_from_metadata(%{component: :bus}), do: :bus
  defp scope_from_metadata(%{component: :dc}), do: :dc
  defp scope_from_metadata(%{component: :slave, slave: name}) when is_atom(name), do: {:slave, name}
  defp scope_from_metadata(%{component: :domain, domain: id}) when is_atom(id), do: {:domain, id}
  defp scope_from_metadata(_meta), do: nil

  defp scope_from_message("[Master]" <> _rest), do: :master
  defp scope_from_message("[Bus]" <> _rest), do: :bus
  defp scope_from_message("[Link." <> _rest), do: :bus
  defp scope_from_message("[DC]" <> _rest), do: :dc

  defp scope_from_message(message) when is_binary(message) do
    cond do
      String.starts_with?(message, "[Slave ") ->
        extract_named_scope(message, ~r/^\[Slave ([^\]]+)\]/, :slave)

      String.starts_with?(message, "[Domain ") ->
        extract_named_scope(message, ~r/^\[Domain ([^\]]+)\]/, :domain)

      true ->
        nil
    end
  end

  defp extract_named_scope(message, pattern, kind) do
    case Regex.run(pattern, message, capture: :all_but_first) do
      [name] ->
        case existing_atom(name) do
          {:ok, atom} -> {kind, atom}
          :error -> nil
        end

      _ ->
        nil
    end
  end

  defp existing_atom(name) when is_binary(name) do
    name
    |> String.trim()
    |> String.trim_leading(":")
    |> case do
      trimmed when trimmed == "" ->
        :error

      trimmed ->
        try do
          {:ok, String.to_existing_atom(trimmed)}
        rescue
          ArgumentError -> :error
        end
    end
  end

  defp format_message({:string, message}) do
    message
    |> IO.chardata_to_string()
    |> String.trim_trailing()
  end

  defp format_message({:report, report}) do
    report
    |> inspect(pretty: false, limit: 20)
    |> String.trim_trailing()
  end

  defp format_message({format, args}) when is_list(args) do
    format
    |> :io_lib.format(args)
    |> IO.iodata_to_binary()
    |> String.trim_trailing()
  rescue
    _ -> inspect({format, args}, pretty: false, limit: 10)
  end

  defp format_message(other) do
    other
    |> inspect(pretty: false, limit: 20)
    |> String.trim_trailing()
  end
end
