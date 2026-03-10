defmodule KinoEtherCAT.WidgetLogs do
  @moduledoc false

  use GenServer

  alias EtherCAT.{Bus, Domain, Master, Slave}

  @handler_id :kino_ethercat_widget_logs
  @default_filter_id :kino_ethercat_widget_logs
  @active_scopes_table :kino_ethercat_widget_log_active_scopes
  @max_entries 200

  @type scope :: :master | :bus | :dc | {:slave, atom()} | {:domain, atom()}
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
        if active_scope?(scope) do
          case Process.whereis(__MODULE__) do
            pid when is_pid(pid) ->
              send(pid, {:append_entry, scope, entry})
              :ok

            _ ->
              :ok
          end
        else
          :ok
        end

      nil ->
        :ok
    end
  end

  @spec silence?(map()) :: boolean()
  def silence?(event) when is_map(event) do
    case log_entry(event) do
      {scope, _entry} -> active_scope?(scope)
      nil -> false
    end
  end

  @spec scope(struct() | scope()) :: {:ok, scope()} | :error
  def scope(%Master{}), do: {:ok, :master}
  def scope(%Bus{}), do: {:ok, :bus}
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
    ensure_active_scopes_table()
    install_logger_integration()

    {:ok,
     %{
       entries: %{},
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

    activate_scope(scope)

    {:reply, :ok, %{state | subscribers: subscribers, monitors: monitors}}
  end

  def handle_call({:entries, scope}, _from, state) do
    {:reply, Map.get(state.entries, scope, []), state}
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

    {subscribers, inactive_scopes} =
      Enum.reduce(state.subscribers, {%{}, []}, fn {scope, pids}, {acc, inactive} ->
        remaining = MapSet.delete(pids, pid)

        if MapSet.size(remaining) == 0 do
          {acc, [scope | inactive]}
        else
          {Map.put(acc, scope, remaining), inactive}
        end
      end)

    Enum.each(inactive_scopes, &deactivate_scope/1)

    entries =
      Enum.reduce(inactive_scopes, state.entries, fn scope, acc ->
        Map.delete(acc, scope)
      end)

    {:noreply, %{state | subscribers: subscribers, monitors: monitors, entries: entries}}
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

  defp ensure_active_scopes_table do
    case :ets.whereis(@active_scopes_table) do
      :undefined ->
        :ets.new(@active_scopes_table, [:named_table, :public, :set, read_concurrency: true])
        :ok

      _table ->
        :ok
    end
  rescue
    ArgumentError -> :ok
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

  defp activate_scope(scope) do
    case :ets.whereis(@active_scopes_table) do
      :undefined -> :ok
      table -> :ets.insert(table, {scope, true})
    end

    :ok
  rescue
    ArgumentError -> :ok
  end

  defp deactivate_scope(scope) do
    case :ets.whereis(@active_scopes_table) do
      :undefined -> :ok
      table -> :ets.delete(table, scope)
    end

    :ok
  rescue
    ArgumentError -> :ok
  end

  defp active_scope?(scope) do
    case :ets.whereis(@active_scopes_table) do
      :undefined -> false
      table -> :ets.member(table, scope)
    end
  rescue
    ArgumentError -> false
  end

  defp notify_subscribers(subscribers, scope) do
    Enum.each(Map.get(subscribers, scope, MapSet.new()), fn pid ->
      send(pid, {:kino_ethercat, :logs_updated, scope})
    end)
  end

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
      nil -> scope_from_message(text)
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

  defp scope_from_message("[Master]" <> _rest), do: :master
  defp scope_from_message("[Bus]" <> _rest), do: :bus
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
