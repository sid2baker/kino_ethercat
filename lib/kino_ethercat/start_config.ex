defmodule KinoEtherCAT.StartConfig do
  @moduledoc false

  use GenServer

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec remember(keyword()) :: :ok
  def remember(opts) when is_list(opts) do
    case Process.whereis(__MODULE__) do
      pid when is_pid(pid) -> GenServer.call(pid, {:remember, opts})
      _ -> :ok
    end
  catch
    :exit, _ -> :ok
  end

  @spec current() :: keyword() | nil
  def current do
    case Process.whereis(__MODULE__) do
      pid when is_pid(pid) -> GenServer.call(pid, :current)
      _ -> nil
    end
  catch
    :exit, _ -> nil
  end

  @spec available?() :: boolean()
  def available?, do: is_list(current())

  @spec clear() :: :ok
  def clear do
    case Process.whereis(__MODULE__) do
      pid when is_pid(pid) -> GenServer.call(pid, :clear)
      _ -> :ok
    end
  catch
    :exit, _ -> :ok
  end

  @impl true
  def init(_opts), do: {:ok, nil}

  @impl true
  def handle_call({:remember, opts}, _from, _state), do: {:reply, :ok, opts}

  def handle_call(:current, _from, state), do: {:reply, state, state}

  def handle_call(:clear, _from, _state), do: {:reply, :ok, nil}
end
