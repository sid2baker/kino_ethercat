defmodule KinoEtherCAT.Runtime.BusResource do
  @moduledoc false

  defstruct [:ref]

  @type t :: %__MODULE__{
          ref: EtherCAT.Bus.server() | nil
        }
end
