defmodule KinoEtherCAT.Introduction.View do
  @moduledoc false

  alias EtherCAT.Simulator
  @spec payload(map() | nil) :: map()
  def payload(message \\ nil) do
    case Simulator.info() do
      {:ok, info} ->
        running_payload(info, master_snapshot(), message)

      {:error, reason} ->
        offline_payload(reason, offline_message(reason, message))
    end
  end

  defp running_payload(info, master, message) do
    connections = Map.get(info, :connections, [])

    %{
      title: "EtherCAT Introduction",
      kind: "simulator-first lesson",
      status: "running",
      message: message,
      summary: [
        %{label: "Simulator", value: "running"},
        %{label: "Master", value: Atom.to_string(master.state)},
        %{label: "Connections", value: Integer.to_string(length(connections))},
        %{label: "Domain", value: master.domain_state},
        %{label: "WKC", value: master.wkc}
      ],
      setup_workflow: setup_workflow(master),
      path: learning_path(master),
      state_overview: [
        %{label: "Master state", value: Atom.to_string(master.state)},
        %{label: "What it means", value: state_explanation(master.state)},
        %{label: "Domain health", value: master.domain_health},
        %{label: "Why WKC matters", value: wkc_explanation(master)}
      ]
    }
  end

  defp offline_payload(reason, message) do
    %{
      title: "EtherCAT Introduction",
      kind: "simulator-first lesson",
      status: "offline",
      reason: to_string(reason),
      message: message,
      summary: [
        %{label: "Simulator", value: "offline"},
        %{label: "Master", value: "idle"},
        %{label: "Connections", value: "0"},
        %{label: "Domain", value: "n/a"},
        %{label: "WKC", value: "n/a"}
      ],
      setup_workflow: offline_setup_workflow(),
      path: offline_learning_path(),
      state_overview: [
        %{label: "Master state", value: "idle"},
        %{
          label: "What it means",
          value:
            "Start the simulator smart cell first. Then add the setup smart cell and evaluate the generated code to see PREOP, SAFEOP, and OP in action."
        },
        %{label: "Domain health", value: "No domains running yet."},
        %{label: "Why WKC matters", value: "WKC becomes meaningful once a domain is cycling."}
      ]
    }
  end

  defp learning_path(master) do
    stage = setup_stage(master)

    [
      %{
        title: "1. Evaluate the simulator smart cell",
        state: "done",
        body:
          "Evaluate the generated simulator cell so the teaching workspace and the virtual EtherCAT ring come up."
      },
      %{
        title: "2. Add the EtherCAT Setup smart cell",
        state: if(stage == :waiting_for_setup, do: "current", else: "done"),
        body:
          "This is the real onboarding step. The setup smart cell discovers the simulator ring automatically and turns it into a normal EtherCAT startup flow."
      },
      %{
        title: "3. Evaluate the generated setup cell",
        state:
          case stage do
            :waiting_for_setup -> "next"
            :waiting_for_generated_setup -> "current"
            :configured_session -> "done"
          end,
        body:
          "That is enough for the intro. The generated code starts the master, waits for PREOP readiness, and activates OP so the session becomes real."
      }
    ]
  end

  defp offline_learning_path do
    [
      %{
        title: "1. Start the simulator workspace",
        state: "current",
        body:
          "Use the EtherCAT Simulator smart cell to start the virtual ring and render the teaching tabs."
      },
      %{
        title: "2. Add the EtherCAT Setup smart cell",
        state: "next",
        body:
          "The setup smart cell is the bridge from the simulator to a normal EtherCAT startup flow."
      },
      %{
        title: "3. Evaluate the generated setup cell",
        state: "next",
        body:
          "Discovery happens automatically there. Evaluating the generated code creates the real master session and moves it through PREOP toward OP."
      }
    ]
  end

  defp setup_workflow(%{state: :idle}) do
    [
      %{
        label: "Next step",
        value: "Add the EtherCAT Setup smart cell and evaluate the generated code."
      },
      %{
        label: "Why",
        value:
          "The setup smart cell discovers the simulator ring automatically and generates the startup code for a real EtherCAT master session."
      },
      %{
        label: "Main view after setup",
        value: "Use the generated Master render for lifecycle control and current session state."
      },
      %{
        label: "After that",
        value:
          "Add the EtherCAT Visualizer smart cell if you want a compact signal dashboard after Master."
      }
    ]
  end

  defp setup_workflow(master) do
    if setup_stage(master) == :waiting_for_generated_setup do
      [
        %{
          label: "Current step",
          value:
            "The setup smart cell has already discovered the ring. Now evaluate the generated setup code."
        },
        %{
          label: "What is running now",
          value:
            "This is still the temporary discovery session, not the final configured master session."
        },
        %{
          label: "Main view after setup",
          value:
            "Once the generated code is evaluated, use the Master render for lifecycle control and current session state."
        },
        %{
          label: "After that",
          value:
            "The EtherCAT Visualizer smart cell is a good next step for a compact signal dashboard."
        }
      ]
    else
      [
        %{
          label: "Current focus",
          value: "Stay with the generated Master render for lifecycle control."
        },
        %{
          label: "Setup role",
          value:
            "The setup smart cell is now the source of truth for how this simulator ring becomes a master session."
        },
        %{
          label: "This introduction tab",
          value:
            "Use it for EtherCAT explanations plus domain and WKC context while the Master render handles operations."
        },
        %{
          label: "Next tool",
          value: "Try the EtherCAT Visualizer smart cell for a compact signal dashboard."
        }
      ]
    end
  end

  defp offline_setup_workflow do
    [
      %{label: "First step", value: "Evaluate the EtherCAT Simulator smart cell."},
      %{
        label: "Then",
        value:
          "Add the EtherCAT Setup smart cell and evaluate the generated code. Discovery happens automatically."
      },
      %{
        label: "Main view after setup",
        value: "Use the generated Master render as the primary operational surface."
      },
      %{
        label: "After that",
        value:
          "The EtherCAT Visualizer smart cell is the natural next step for a compact signal dashboard."
      }
    ]
  end

  defp master_snapshot do
    state =
      case safe(fn -> EtherCAT.state() end, :idle) do
        value when is_atom(value) -> value
        _ -> :idle
      end

    case first_domain_snapshot() do
      nil ->
        %{
          state: state,
          wkc: "n/a",
          domain_health: "No domains running yet.",
          domain_state: "n/a",
          configured_session?: false
        }

      domain ->
        %{
          state: state,
          wkc: domain_wkc(domain),
          domain_health: domain_health(domain),
          domain_state: domain_state(domain),
          configured_session?: true
        }
    end
  end

  defp setup_stage(%{configured_session?: true}), do: :configured_session
  defp setup_stage(%{state: :idle}), do: :waiting_for_setup
  defp setup_stage(_master), do: :waiting_for_generated_setup

  defp first_domain_snapshot do
    case safe(fn -> EtherCAT.domains() end, []) do
      [{id, _cycle_time_us, _pid} | _rest] ->
        case safe(fn -> EtherCAT.domain_info(id) end, {:error, :not_found}) do
          {:ok, info} -> info
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp domain_state(info), do: info |> Map.get(:state, :unknown) |> to_string()

  defp domain_wkc(%{
         expected_wkc: expected,
         cycle_health: {:invalid, {:wkc_mismatch, %{actual: actual}}}
       })
       when is_integer(expected) and is_integer(actual),
       do: "#{actual} / #{expected}"

  defp domain_wkc(%{expected_wkc: expected}) when is_integer(expected),
    do: Integer.to_string(expected)

  defp domain_wkc(_info), do: "n/a"

  defp domain_health(%{cycle_health: :healthy}), do: "Healthy cycle"
  defp domain_health(%{cycle_health: {:invalid, reason}}), do: "Invalid: #{inspect(reason)}"
  defp domain_health(%{cycle_health: value}), do: format_value(value)
  defp domain_health(_info), do: "No domains running yet."

  defp state_explanation(:idle),
    do:
      "No master session is running yet. This is the right moment to scan the simulator from the setup smart cell."

  defp state_explanation(:awaiting_preop),
    do:
      "The master has found the ring and is waiting for slaves to reach PREOP, the configuration-ready state."

  defp state_explanation(:preop_ready),
    do:
      "The bus is configured and ready, but cyclic process-data exchange has not entered OP yet."

  defp state_explanation(:operational),
    do:
      "The master is in OP, so cyclic process data is exchanging and WKC/health checks matter on every cycle."

  defp state_explanation(:deactivated),
    do:
      "The session is alive below OP. This keeps the system inspectable without tearing it down."

  defp state_explanation(:recovering),
    do:
      "The master detected a runtime problem and is driving the ring back toward the desired target."

  defp state_explanation(:activation_blocked),
    do: "The master cannot safely enter OP yet. Domain or DC prerequisites are still failing."

  defp state_explanation(other),
    do:
      "The current master state is #{other}. Use it as a cue for what stage of the EtherCAT lifecycle you are in."

  defp wkc_explanation(%{wkc: "n/a"}) do
    "WKC is the working counter. It becomes interesting once a domain is cycling and the master can compare actual vs expected responses."
  end

  defp wkc_explanation(%{wkc: wkc, domain_health: "Healthy cycle"}) do
    "The domain is healthy and WKC=#{wkc}, which means the master saw the expected slaves respond in this cycle."
  end

  defp wkc_explanation(%{wkc: wkc, domain_health: health}) do
    "WKC=#{wkc} while domain health is '#{health}'. A mismatch is a concrete sign that a cyclic exchange did not involve the expected slaves."
  end

  defp safe(fun, fallback) do
    fun.()
  rescue
    _ -> fallback
  catch
    :exit, _ -> fallback
  end

  defp offline_message(_reason, %{level: "error"} = message), do: message
  defp offline_message(reason, _message), do: error_message("Simulator unavailable: #{reason}.")
  defp error_message(text), do: %{level: "error", text: text}

  defp format_value(nil), do: "nil"
  defp format_value(value) when is_binary(value), do: inspect(value)
  defp format_value(value), do: inspect(value, limit: 4, printable_limit: 120)
end
