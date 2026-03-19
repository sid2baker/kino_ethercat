defmodule KinoEtherCAT.Simulator.View do
  @moduledoc false

  alias KinoEtherCAT.Simulator.Snapshot

  @spec payload(map() | nil) :: map()
  def payload(message \\ nil) do
    snapshot = Snapshot.payload(message)

    Map.put(
      snapshot,
      :fault_summary,
      [
        %{label: "Runtime", value: snapshot.runtime_faults.summary},
        %{label: "Next runtime", value: snapshot.runtime_faults.next_label || "none"}
      ] ++ maybe_transport_fault_summary(snapshot.transport_faults)
    )
  end

  defp maybe_transport_fault_summary(%{enabled: false}), do: []

  defp maybe_transport_fault_summary(%{next_label: next_label} = transport_faults)
       when is_binary(next_label) do
    [
      %{label: "Transport", value: transport_faults.summary},
      %{label: "Next transport", value: next_label}
    ]
  end

  defp maybe_transport_fault_summary(%{enabled: true} = transport_faults) do
    [%{label: "Transport", value: transport_faults.summary}]
  end
end
