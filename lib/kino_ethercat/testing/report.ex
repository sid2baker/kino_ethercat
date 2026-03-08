defmodule KinoEtherCAT.Testing.Report do
  @moduledoc false

  @enforce_keys [:scenario_name, :status, :step_results, :options]
  defstruct [
    :scenario_name,
    :status,
    :started_at_ms,
    :finished_at_ms,
    :duration_ms,
    :failure,
    step_results: [],
    telemetry_events: [],
    options: %{}
  ]

  @type status :: :passed | :failed | :cancelled

  @type step_result :: %{
          index: non_neg_integer(),
          title: String.t(),
          kind: atom(),
          status: :passed | :failed | :awaiting_input,
          started_at_ms: integer(),
          finished_at_ms: integer(),
          duration_ms: integer(),
          detail: String.t() | nil,
          observations: [map()]
        }

  @type telemetry_event :: %{
          id: integer(),
          at_ms: integer(),
          group: atom(),
          event: String.t(),
          detail: String.t()
        }

  @type t :: %__MODULE__{
          scenario_name: String.t(),
          status: status(),
          started_at_ms: integer() | nil,
          finished_at_ms: integer() | nil,
          duration_ms: integer() | nil,
          step_results: [step_result()],
          telemetry_events: [telemetry_event()],
          options: map(),
          failure: String.t() | nil
        }
end
