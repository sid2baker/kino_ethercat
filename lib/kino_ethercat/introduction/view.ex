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
      kind: "phase 1 and 2",
      status: "running",
      message: message,
      summary: [
        %{label: "Simulator", value: "running"},
        %{label: "Ring", value: ring_label(info)},
        %{label: "Connections", value: Integer.to_string(length(connections))},
        %{label: "Master", value: Atom.to_string(master.state)},
        %{label: "WKC", value: master.wkc}
      ],
      mental_model: mental_model_items(),
      first_contact: first_contact_steps(info, master),
      next_after_intro: next_after_intro(master),
      state_overview: current_state_overview(master)
    }
  end

  defp offline_payload(reason, message) do
    %{
      title: "EtherCAT Introduction",
      kind: "phase 1 and 2",
      status: "offline",
      reason: to_string(reason),
      message: message,
      summary: [
        %{label: "Simulator", value: "offline"},
        %{label: "Ring", value: "not running"},
        %{label: "Connections", value: "0"},
        %{label: "Master", value: "idle"},
        %{label: "WKC", value: "n/a"}
      ],
      mental_model: mental_model_items(),
      first_contact: offline_first_contact_steps(),
      next_after_intro: offline_next_after_intro(),
      state_overview: offline_state_overview()
    }
  end

  defp mental_model_items do
    [
      %{
        label: "Master",
        value: "The master drives startup, state transitions, and each cyclic exchange."
      },
      %{
        label: "Slaves",
        value:
          "Slaves expose process data. They respond to the master rather than running the bus."
      },
      %{
        label: "Process image",
        value:
          "Inputs and outputs are treated as one shared image that gets refreshed on every cycle."
      },
      %{
        label: "Cyclic exchange",
        value:
          "Each cycle sends output data, receives input data back, and checks whether the expected devices answered."
      },
      %{
        label: "States",
        value:
          "PREOP is for configuration, SAFEOP validates readiness, and OP is the state where cyclic process data matters."
      }
    ]
  end

  defp first_contact_steps(info, master) do
    loopback = loopback_text(Map.get(info, :connections, []))
    connected? = Map.get(info, :connections, []) != []
    setup_stage = setup_stage(master)

    [
      %{
        title: "1. Stay with one signal path",
        state: if(connected?, do: "done", else: "current"),
        body:
          "#{loopback} Keep the topology small so the process image feels concrete instead of abstract."
      },
      %{
        title: "2. Use the EtherCAT Setup smart cell",
        state: setup_step_state(setup_stage),
        body:
          "Use Setup to turn the simulator ring #{ring_label(info)} into a real EtherCAT master configuration."
      },
      %{
        title: "3. Evaluate the generated setup cell",
        state: setup_eval_step_state(setup_stage),
        body:
          "That starts the master session and makes the Master render the main place to watch PREOP, OP, WKC, and domain health."
      }
    ]
  end

  defp offline_first_contact_steps do
    [
      %{
        title: "1. Start the simulator smart cell",
        state: "current",
        body:
          "Start with the default `coupler -> inputs -> outputs` ring. The simulator is the teaching environment for the first lessons."
      },
      %{
        title: "2. Keep the default loopback",
        state: "next",
        body:
          "The intended first path is `outputs.ch1 -> inputs.ch1`, because it makes the process image easy to predict."
      },
      %{
        title: "3. Use the EtherCAT Setup smart cell",
        state: "next",
        body: "Setup is the bridge from the teaching ring into a real EtherCAT master session."
      }
    ]
  end

  defp next_after_intro(%{state: :idle}) do
    [
      %{
        label: "Next step",
        value:
          "Use the EtherCAT Setup smart cell and evaluate the generated code. That moves you from a teaching ring to a real master session."
      },
      %{
        label: "Why",
        value:
          "Phase 3 starts when the setup flow discovers the ring, reaches PREOP, and hands control to the Master render."
      },
      %{
        label: "Main surface",
        value: "Use the generated Master render for PREOP, SAFEOP, OP, domain health, and WKC."
      },
      %{
        label: "What changes next",
        value:
          "You stop looking only at signals and start looking at EtherCAT lifecycle, validity, and readiness."
      }
    ]
  end

  defp next_after_intro(master) do
    if setup_stage(master) == :waiting_for_generated_setup do
      [
        %{
          label: "Current step",
          value:
            "The setup smart cell has already discovered the ring. Evaluate its generated code to turn discovery into a configured master session."
        },
        %{
          label: "Why this matters",
          value:
            "The discovery session is temporary. The generated setup code is what actually defines the master, domains, and activation path."
        },
        %{
          label: "Main surface",
          value: "Once that cell is evaluated, use the Master render as the primary runtime view."
        },
        %{
          label: "What changes next",
          value:
            "You move into phase 3: PREOP readiness, OP activation, domain validity, and WKC interpretation."
        }
      ]
    else
      [
        %{
          label: "Current focus",
          value:
            "You are already beyond phase 2. Stay with the Master render for lifecycle control."
        },
        %{
          label: "What phase 3 adds",
          value:
            "You can now see PREOP, SAFEOP, OP, domain health, and WKC as part of a real master session."
        },
        %{
          label: "Setup role",
          value:
            "The setup smart cell is now the source of truth for how this simulator ring becomes an EtherCAT session."
        },
        %{
          label: "Later",
          value:
            "Once the baseline is clear, the simulator fault console is the natural entry to phase 4."
        }
      ]
    end
  end

  defp offline_next_after_intro do
    [
      %{
        label: "Next step",
        value:
          "After the simulator is running and the first loopback is visible, use the EtherCAT Setup smart cell."
      },
      %{
        label: "Why",
        value:
          "That is the bridge from a pure teaching ring into the real master lifecycle: discovery, PREOP, SAFEOP, and OP."
      },
      %{
        label: "Main surface",
        value:
          "The generated Master render becomes the primary view once setup code is evaluated."
      },
      %{
        label: "What changes next",
        value: "The focus shifts from signals to lifecycle and runtime health."
      }
    ]
  end

  defp current_state_overview(master) do
    [
      %{label: "Master state", value: Atom.to_string(master.state)},
      %{label: "What you are seeing", value: state_explanation(master.state)},
      %{label: "Domain health", value: master.domain_health},
      %{label: "Why WKC matters", value: wkc_explanation(master)}
    ]
  end

  defp offline_state_overview do
    [
      %{label: "Master state", value: "idle"},
      %{
        label: "What you are seeing",
        value:
          "No master session is running yet. That is fine for phase 1 and 2, because the simulator ring comes first."
      },
      %{label: "Domain health", value: "No domains running yet."},
      %{label: "Why WKC matters", value: "WKC becomes meaningful once a domain is cycling."}
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
          configured_session?: false
        }

      domain ->
        %{
          state: state,
          wkc: domain_wkc(domain),
          domain_health: domain_health(domain),
          configured_session?: true
        }
    end
  end

  defp setup_stage(%{configured_session?: true}), do: :configured_session
  defp setup_stage(%{state: :idle}), do: :waiting_for_setup
  defp setup_stage(_master), do: :waiting_for_generated_setup

  defp setup_step_state(:waiting_for_setup), do: "current"
  defp setup_step_state(_stage), do: "done"

  defp setup_eval_step_state(:waiting_for_setup), do: "next"
  defp setup_eval_step_state(:waiting_for_generated_setup), do: "current"
  defp setup_eval_step_state(_stage), do: "done"

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

  defp ring_label(info) do
    info
    |> Map.get(:slaves, [])
    |> Enum.map_join(" -> ", &Atom.to_string(&1.name))
    |> case do
      "" -> "not discovered"
      ring -> ring
    end
  end

  defp loopback_text(connections) do
    case preferred_connection(connections) do
      %{source: {source_slave, source_signal}, target: {target_slave, target_signal}} ->
        "The active loopback is #{source_slave}.#{source_signal} -> #{target_slave}.#{target_signal}."

      nil ->
        "No simulator signal connection is active yet. Reset to the default loopback or add one in Expert mode."
    end
  end

  defp preferred_connection(connections) do
    Enum.find(connections, fn
      %{source: {:outputs, :ch1}, target: {:inputs, :ch1}} -> true
      _other -> false
    end) || List.first(connections)
  end

  defp state_explanation(:idle),
    do:
      "No master session is running yet. That is still fine for phase 1 and 2, because the simulator ring exists independently."

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
