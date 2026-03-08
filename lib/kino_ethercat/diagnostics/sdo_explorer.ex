defmodule KinoEtherCAT.SDOExplorer do
  @moduledoc """
  Live mailbox / SDO explorer for CoE-capable EtherCAT slaves.

  The explorer discovers CoE slaves at runtime, performs blocking SDO uploads
  and downloads through `EtherCAT.upload_sdo/3` and `EtherCAT.download_sdo/4`,
  and keeps recent operations visible in the notebook.
  """

  use Kino.JS, assets_path: "lib/assets/sdo_explorer/build"
  use Kino.JS.Live

  @history_limit 12

  @doc false
  def new(opts \\ []) do
    Kino.JS.Live.new(__MODULE__, normalize_opts(opts))
  end

  @impl true
  def init(opts, ctx) do
    state =
      %{
        opts: opts,
        slaves: [],
        slave_lookup: %{},
        selected_slave: nil,
        result: nil,
        history: []
      }
      |> refresh_slaves()

    {:ok, assign(ctx, state)}
  end

  @impl true
  def handle_connect(ctx) do
    {:ok, payload(ctx.assigns), ctx}
  end

  @impl true
  def handle_event("refresh_slaves", _params, ctx) do
    state = refresh_slaves(ctx.assigns)
    broadcast_event(ctx, "snapshot", payload(state))
    {:noreply, assign(ctx, state)}
  end

  def handle_event("run", params, ctx) do
    state =
      case run_operation(ctx.assigns, params) do
        {:ok, state} -> state
        {:error, state} -> state
      end

    broadcast_event(ctx, "snapshot", payload(state))
    {:noreply, assign(ctx, state)}
  end

  @doc false
  def parse_integer(value) when is_binary(value) do
    value = String.trim(value)

    cond do
      value == "" ->
        {:error, :empty}

      String.starts_with?(String.downcase(value), "0x") ->
        parse_hex_integer(String.slice(value, 2..-1//1))

      true ->
        case Integer.parse(value) do
          {integer, ""} when integer >= 0 -> {:ok, integer}
          _ -> {:error, :invalid_integer}
        end
    end
  end

  @doc false
  def parse_hex_payload(value) when is_binary(value) do
    digits =
      value
      |> String.replace(~r/[^0-9A-Fa-f]/u, "")
      |> String.upcase()

    cond do
      digits == "" ->
        {:ok, <<>>}

      rem(byte_size(digits), 2) != 0 ->
        {:error, :odd_length}

      true ->
        decode_hex_pairs(digits, <<>>)
    end
  end

  @doc false
  def format_binary(binary) when is_binary(binary) do
    %{
      bytes: byte_size(binary),
      hex:
        binary
        |> :binary.bin_to_list()
        |> Enum.map_join(" ", &String.pad_leading(Integer.to_string(&1, 16), 2, "0"))
        |> String.upcase(),
      ascii:
        binary
        |> :binary.bin_to_list()
        |> Enum.map_join(fn
          byte when byte in 32..126 -> <<byte>>
          _ -> "."
        end)
    }
  end

  defp normalize_opts(opts) do
    [
      slave: opts[:slave],
      index: Keyword.get(opts, :index, 0x1018),
      subindex: Keyword.get(opts, :subindex, 0),
      write_data: Keyword.get(opts, :write_data, "")
    ]
  end

  defp payload(state) do
    %{
      slaves: state.slaves,
      selected_slave: state.selected_slave,
      default_index: integer_to_hex(state.opts[:index], 4),
      default_subindex: integer_to_hex(state.opts[:subindex], 2),
      default_write_data: state.opts[:write_data],
      result: state.result,
      history: state.history
    }
  end

  defp refresh_slaves(state) do
    slaves = fetch_coe_slaves()
    slave_lookup = Map.new(slaves, &{&1.name, String.to_existing_atom(&1.name)})

    selected_slave =
      cond do
        state.selected_slave in Map.keys(slave_lookup) ->
          state.selected_slave

        is_atom(state.opts[:slave]) ->
          preferred = Atom.to_string(state.opts[:slave])
          if preferred in Map.keys(slave_lookup), do: preferred, else: default_slave_name(slaves)

        true ->
          default_slave_name(slaves)
      end

    state
    |> Map.put(:slaves, slaves)
    |> Map.put(:slave_lookup, slave_lookup)
    |> Map.put(:selected_slave, selected_slave)
  rescue
    _ ->
      state
      |> Map.put(:slaves, [])
      |> Map.put(:slave_lookup, %{})
      |> Map.put(:selected_slave, nil)
  end

  defp fetch_coe_slaves do
    EtherCAT.slaves()
    |> Enum.flat_map(fn %{name: name, station: station} ->
      case EtherCAT.slave_info(name) do
        {:ok, %{coe: true}} ->
          [%{name: to_string(name), station: station, label: "#{name} @ #{integer_to_hex(station, 4)}"}]

        _ ->
          []
      end
    end)
  end

  defp run_operation(state, params) do
    with {:ok, slave_name} <- fetch_slave(state, params["slave"]),
         {:ok, index} <- parse_integer(params["index"] || ""),
         {:ok, subindex} <- parse_integer(params["subindex"] || ""),
         {:ok, operation} <- normalize_operation(params["operation"]) do
      execute_operation(state, slave_name, index, subindex, operation, params["write_data"] || "")
    else
      {:error, reason} ->
        {:error, put_result(state, error_result(reason, params))}
    end
  end

  defp execute_operation(state, slave_name, index, subindex, :upload, _write_data) do
    case EtherCAT.upload_sdo(slave_name, index, subindex) do
      {:ok, binary} ->
        result =
          success_result(
            :upload,
            Atom.to_string(slave_name),
            index,
            subindex,
            binary
          )

        {:ok, put_result(state, result)}

      {:error, reason} ->
        {:error,
         put_result(
           state,
           error_result(reason, %{
             "operation" => "upload",
             "slave" => Atom.to_string(slave_name),
             "index" => integer_to_hex(index, 4),
             "subindex" => integer_to_hex(subindex, 2)
           })
         )}
    end
  end

  defp execute_operation(state, slave_name, index, subindex, :download, write_data) do
    with {:ok, binary} <- parse_hex_payload(write_data),
         :ok <- EtherCAT.download_sdo(slave_name, index, subindex, binary) do
      result =
        success_result(
          :download,
          Atom.to_string(slave_name),
          index,
          subindex,
          binary
        )

      {:ok, put_result(state, result)}
    else
      {:error, reason} ->
        {:error,
         put_result(
           state,
           error_result(reason, %{
             "operation" => "download",
             "slave" => Atom.to_string(slave_name),
             "index" => integer_to_hex(index, 4),
             "subindex" => integer_to_hex(subindex, 2)
           })
         )}
    end
  end

  defp fetch_slave(_state, nil), do: {:error, :missing_slave}
  defp fetch_slave(_state, ""), do: {:error, :missing_slave}

  defp fetch_slave(state, slave_name) do
    case Map.fetch(state.slave_lookup, slave_name) do
      {:ok, atom_name} -> {:ok, atom_name}
      :error -> {:error, :unknown_slave}
    end
  end

  defp normalize_operation("upload"), do: {:ok, :upload}
  defp normalize_operation("download"), do: {:ok, :download}
  defp normalize_operation(_other), do: {:error, :invalid_operation}

  defp put_result(state, result) do
    history_entry = Map.take(result, [:status, :operation, :slave, :index, :subindex, :bytes, :hex, :message, :at_ms])

    state
    |> Map.put(:result, result)
    |> Map.update!(:history, fn history -> [history_entry | history] |> Enum.take(@history_limit) end)
  end

  defp success_result(operation, slave_name, index, subindex, binary) do
    formatted = format_binary(binary)

    %{
      status: "ok",
      operation: Atom.to_string(operation),
      slave: slave_name,
      index: integer_to_hex(index, 4),
      subindex: integer_to_hex(subindex, 2),
      bytes: formatted.bytes,
      hex: formatted.hex,
      ascii: formatted.ascii,
      message:
        case operation do
          :upload -> "uploaded #{formatted.bytes} byte(s)"
          :download -> "downloaded #{formatted.bytes} byte(s)"
        end,
      at_ms: now_ms()
    }
  end

  defp error_result(reason, params) do
    %{
      status: "error",
      operation: params["operation"] || "upload",
      slave: params["slave"] || "",
      index: params["index"] || "",
      subindex: params["subindex"] || "",
      bytes: nil,
      hex: nil,
      ascii: nil,
      message: format_reason(reason),
      at_ms: now_ms()
    }
  end

  defp parse_hex_integer(""), do: {:error, :empty}

  defp parse_hex_integer(value) do
    case Integer.parse(value, 16) do
      {integer, ""} when integer >= 0 -> {:ok, integer}
      _ -> {:error, :invalid_hex}
    end
  end

  defp decode_hex_pairs(<<>>, acc), do: {:ok, acc}

  defp decode_hex_pairs(<<hi::binary-size(1), lo::binary-size(1), rest::binary>>, acc) do
    case Integer.parse(hi <> lo, 16) do
      {byte, ""} -> decode_hex_pairs(rest, <<acc::binary, byte>>)
      _ -> {:error, :invalid_hex_payload}
    end
  end

  defp default_slave_name([]), do: nil
  defp default_slave_name([slave | _]), do: slave.name

  defp integer_to_hex(value, pad) when is_integer(value) and value >= 0 do
    "0x" <> String.upcase(String.pad_leading(Integer.to_string(value, 16), pad, "0"))
  end

  defp format_reason(:missing_slave), do: "pick a CoE slave first"
  defp format_reason(:unknown_slave), do: "selected slave is no longer available"
  defp format_reason(:invalid_operation), do: "invalid mailbox operation"
  defp format_reason(:empty), do: "index or subindex is empty"
  defp format_reason(:odd_length), do: "hex payload must contain full bytes"
  defp format_reason(:invalid_integer), do: "index and subindex must be integers"
  defp format_reason(:invalid_hex), do: "hex number is invalid"
  defp format_reason(:invalid_hex_payload), do: "hex payload contains invalid bytes"
  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)

  defp now_ms, do: System.system_time(:millisecond)
end
