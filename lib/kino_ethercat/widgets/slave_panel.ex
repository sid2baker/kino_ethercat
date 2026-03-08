defmodule KinoEtherCAT.Widgets.SlavePanel do
  @moduledoc """
  Aggregated live panel for one EtherCAT slave.

  The panel batches process-data updates, seeds input values from the latest
  process image, and keeps manual output writes and runtime errors visible in a
  single place.
  """

  use Kino.JS, assets_path: "lib/assets/slave_panel/build"
  use Kino.JS.Live

  alias KinoEtherCAT.Widgets.SlaveSnapshot

  @default_batch_ms 100

  @doc false
  def new(slave_name, opts \\ []) do
    Kino.JS.Live.new(__MODULE__, {slave_name, opts})
  end

  @impl true
  def init({slave_name, opts}, ctx) do
    opts = normalize_opts(opts)

    state =
      %{
        slave_name: slave_name,
        opts: opts,
        info: nil,
        signal_meta: %{},
        subscribed: MapSet.new(),
        values: %{},
        pending: %{},
        flush_scheduled?: false,
        write_error: nil,
        runtime_error: nil,
        domains: [],
        snapshot: %{}
      }
      |> refresh_runtime(subscribe?: true)

    {:ok, assign(ctx, state)}
  end

  @impl true
  def handle_connect(ctx) do
    {:ok, ctx.assigns.snapshot, ctx}
  end

  @impl true
  def handle_event("refresh", _params, ctx) do
    state =
      ctx.assigns
      |> merge_pending()
      |> refresh_runtime(subscribe?: true)

    broadcast_event(ctx, "snapshot", state.snapshot)
    {:noreply, assign(ctx, state)}
  end

  def handle_event("set_output", %{"signal" => signal_name, "value" => raw_value}, ctx) do
    case write_output(ctx.assigns, signal_name, raw_value) do
      {:ok, state} ->
        broadcast_event(ctx, "snapshot", state.snapshot)
        {:noreply, assign(ctx, state)}

      {:error, reason} ->
        state = put_write_error(ctx.assigns, signal_name, reason)
        broadcast_event(ctx, "snapshot", state.snapshot)
        {:noreply, assign(ctx, state)}
    end
  end

  @impl true
  def handle_info({:ethercat, :signal, slave_name, signal_name, value}, ctx)
      when slave_name == ctx.assigns.slave_name do
    state =
      ctx.assigns
      |> update_in([:pending], &Map.put(&1, signal_name, value))
      |> schedule_flush()

    {:noreply, assign(ctx, state)}
  end

  def handle_info(:flush, ctx) do
    state =
      ctx.assigns
      |> merge_pending()
      |> Map.put(:flush_scheduled?, false)
      |> rebuild_snapshot()

    broadcast_event(ctx, "snapshot", state.snapshot)
    {:noreply, assign(ctx, state)}
  end

  defp normalize_opts(opts) do
    opts
    |> Keyword.put_new(:batch_ms, @default_batch_ms)
    |> Keyword.put_new(:show_identity?, true)
    |> Keyword.put_new(:show_domains?, true)
  end

  defp refresh_runtime(state, opts) do
    case EtherCAT.slave_info(state.slave_name) do
      {:ok, info} ->
        {subscribed, runtime_error} =
          ensure_subscriptions(state.slave_name, info.signals, state.subscribed)

        values =
          state.values
          |> Map.merge(seed_input_values(state.slave_name, info.signals))

        state
        |> Map.merge(%{
          info: info,
          signal_meta: signal_meta(info.signals),
          subscribed: subscribed,
          values: values,
          domains: fetch_domains(info.signals),
          runtime_error: runtime_error,
          write_error: state.write_error
        })
        |> rebuild_snapshot()
        |> maybe_refresh_again(opts)

      {:error, reason} ->
        state
        |> Map.put(:runtime_error, reason)
        |> rebuild_snapshot()
        |> maybe_refresh_again(opts)
    end
  end

  defp maybe_refresh_again(state, _opts), do: state

  defp ensure_subscriptions(slave_name, signals, subscribed) do
    Enum.reduce(signals, {subscribed, nil}, fn signal, {acc, error} ->
      cond do
        MapSet.member?(acc, signal.name) ->
          {acc, error}

        true ->
          case EtherCAT.subscribe(slave_name, signal.name) do
            :ok -> {MapSet.put(acc, signal.name), error}
            {:error, reason} -> {acc, reason}
          end
      end
    end)
  end

  defp signal_meta(signals) do
    Map.new(signals, fn signal ->
      {to_string(signal.name),
       %{
         name: signal.name,
         direction: signal.direction,
         bit_size: signal.bit_size,
         domain: signal.domain
       }}
    end)
  end

  defp seed_input_values(slave_name, signals) do
    signals
    |> Enum.filter(&(&1.direction == :input))
    |> Enum.reduce(%{}, fn signal, acc ->
      case EtherCAT.read_input(slave_name, signal.name) do
        {:ok, value} -> Map.put(acc, signal.name, value)
        _ -> acc
      end
    end)
  end

  defp fetch_domains(signals) do
    signals
    |> Enum.map(& &1.domain)
    |> Enum.uniq()
    |> Enum.map(fn domain_id ->
      info =
        case EtherCAT.domain_info(domain_id) do
          {:ok, domain_info} -> domain_info
          {:error, _} -> %{}
        end

      %{
        id: to_string(domain_id),
        state: to_string(Map.get(info, :state, :unknown)),
        miss_count: Map.get(info, :miss_count, 0),
        total_miss_count: Map.get(info, :total_miss_count, 0),
        expected_wkc: Map.get(info, :expected_wkc, 0)
      }
    end)
  rescue
    _ -> []
  end

  defp schedule_flush(%{flush_scheduled?: true} = state), do: state

  defp schedule_flush(state) do
    Process.send_after(self(), :flush, state.opts[:batch_ms])
    Map.put(state, :flush_scheduled?, true)
  end

  defp merge_pending(state) when map_size(state.pending) == 0, do: state

  defp merge_pending(state) do
    state
    |> update_in([:values], &Map.merge(&1, state.pending))
    |> Map.put(:pending, %{})
  end

  defp rebuild_snapshot(state) do
    snapshot =
      SlaveSnapshot.build(
        state.slave_name,
        state.info,
        state.values,
        state.domains,
        state.write_error,
        state.runtime_error,
        state.opts
      )

    Map.put(state, :snapshot, snapshot)
  end

  defp write_output(state, signal_name, raw_value) do
    with {:ok, signal} <- fetch_output_signal(state.signal_meta, signal_name),
         {:ok, value} <- normalize_output_value(signal, raw_value),
         :ok <- EtherCAT.write_output(state.slave_name, signal.name, value) do
      new_state =
        state
        |> Map.put(:write_error, nil)
        |> update_in([:values], &Map.put(&1, signal.name, value))
        |> rebuild_snapshot()

      {:ok, new_state}
    end
  end

  defp fetch_output_signal(signal_meta, signal_name) do
    case Map.get(signal_meta, signal_name) do
      %{direction: :output} = signal -> {:ok, signal}
      _ -> {:error, :not_output_signal}
    end
  end

  defp normalize_output_value(%{bit_size: 1}, value) when value in [0, 1], do: {:ok, value}

  defp normalize_output_value(%{bit_size: 1}, value) when value in ["0", "1"] do
    {:ok, String.to_integer(value)}
  end

  defp normalize_output_value(%{bit_size: 1}, true), do: {:ok, 1}
  defp normalize_output_value(%{bit_size: 1}, false), do: {:ok, 0}
  defp normalize_output_value(_signal, _value), do: {:error, :unsupported_value}

  defp put_write_error(state, signal_name, reason) do
    state
    |> Map.put(:write_error, %{signal: signal_name, reason: reason})
    |> rebuild_snapshot()
  end
end
