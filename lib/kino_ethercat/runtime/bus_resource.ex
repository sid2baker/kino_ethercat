defmodule KinoEtherCAT.Runtime.BusResource do
  @moduledoc """
  Renderable reference to the current EtherCAT bus runtime.

  This is returned by `KinoEtherCAT.bus/0` and `KinoEtherCAT.Runtime.bus/0`.
  """

  defstruct [:ref]

  @type t :: %__MODULE__{
          ref: EtherCAT.Bus.server() | nil
        }
end
