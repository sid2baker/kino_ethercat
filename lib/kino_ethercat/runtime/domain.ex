defmodule KinoEtherCAT.Runtime.Domain do
  @moduledoc false

  use Kino.JS, assets_path: "lib/assets/runtime_panel/build"
  use Kino.JS.Live

  alias KinoEtherCAT.Runtime.Live

  @spec new(EtherCAT.Domain.t()) :: Kino.JS.Live.t()
  def new(resource), do: Kino.JS.Live.new(__MODULE__, resource)

  @impl true
  def init(resource, ctx), do: Live.init(resource, ctx)

  @impl true
  def handle_connect(ctx), do: Live.handle_connect(ctx)

  @impl true
  def handle_event(event, params, ctx), do: Live.handle_event(event, params, ctx)
end
