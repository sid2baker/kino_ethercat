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
      ] ++ maybe_udp_fault_summary(snapshot.udp_faults)
    )
  end

  defp maybe_udp_fault_summary(%{enabled: true} = udp_faults) do
    [
      %{label: "UDP", value: udp_faults.summary},
      %{label: "Next UDP", value: udp_faults.next_label || "none"}
    ]
  end

  defp maybe_udp_fault_summary(_udp_faults), do: []
end
