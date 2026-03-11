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

  @spec perform(String.t(), map()) :: map()
  def perform("set_output", %{"slave" => raw_slave, "signal" => raw_signal, "value" => raw_value}) do
    with {:ok, slave_name} <- resolve_slave_name(raw_slave),
         {:ok, signal_name} <- resolve_signal_name(raw_signal),
         {:ok, value} <- parse_bit_value(raw_value) do
      invoke(
        fn -> Simulator.set_value(slave_name, signal_name, value) end,
        info_message("Set #{raw_slave}.#{raw_signal} to #{value}.")
      )
    else
      {:error, :invalid_slave} -> error_message("Select a known simulator slave.")
      {:error, :invalid_signal} -> error_message("Select a known simulator signal.")
      {:error, :invalid_value} -> error_message("Teaching playground outputs expect 0 or 1.")
    end
  end

  def perform("reset_outputs", _params) do
    with {:ok, refs} <- output_refs() do
      invoke_many(
        Enum.map(refs, fn {slave_name, signal_name} ->
          {fn -> Simulator.set_value(slave_name, signal_name, 0) end, []}
        end),
        info_message("Reset connected outputs to 0.")
      )
    else
      {:error, :no_outputs} -> error_message("No connected output signals found.")
      {:error, :not_found} -> error_message("Simulator unavailable.")
    end
  end

  def perform(_action, _params), do: error_message("Unknown introduction action.")

  defp running_payload(info, master, message) do
    connections = Map.get(info, :connections, [])
    rows = playground_rows(info, connections)

    %{
      title: "EtherCAT Introduction",
      kind: "simulator-first lesson",
      status: "running",
      message: message,
      summary: [
        %{label: "Simulator", value: "running"},
        %{label: "Master", value: Atom.to_string(master.state)},
        %{label: "Connections", value: Integer.to_string(length(rows))},
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
      ],
      playground: %{
        hint: playground_hint(rows, master.state),
        rows: rows
      }
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
            "Start the simulator smart cell first. Then scan it from the setup smart cell to see PREOP, SAFEOP, and OP in action."
        },
        %{label: "Domain health", value: "No domains running yet."},
        %{label: "Why WKC matters", value: "WKC becomes meaningful once a domain is cycling."}
      ],
      playground: %{
        hint: "No simulator ring is running yet.",
        rows: []
      }
    }
  end

  defp learning_path(master) do
    [
      %{
        title: "1. Evaluate the simulator smart cell",
        state: "done",
        body:
          "Evaluate the generated simulator cell so the teaching workspace and the virtual EtherCAT ring come up."
      },
      %{
        title: "2. Add the EtherCAT Setup smart cell and click Scan Bus",
        state: if(master.state == :idle, do: "current", else: "done"),
        body:
          "This is the real onboarding step. The setup smart cell discovers the simulator ring and turns it into a normal EtherCAT startup flow."
      },
      %{
        title: "3. Evaluate the generated setup cell",
        state: if(master.state == :idle, do: "next", else: "done"),
        body:
          "That generated code starts the master, waits for PREOP readiness, and activates OP so the session becomes real."
      },
      %{
        title: "4. Use the Master render as your main control surface",
        state: if(master.state == :idle, do: "next", else: "current"),
        body:
          "Once the setup cell has been evaluated, the Master render is the place to watch lifecycle state and control activate, deactivate, and stop."
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
        title: "3. Click Scan Bus and evaluate the generated setup cell",
        state: "next",
        body: "That creates the real master session and moves it through PREOP toward OP."
      },
      %{
        title: "4. Use the Master render",
        state: "next",
        body:
          "The Master render becomes the main operational surface once the setup cell has been evaluated."
      }
    ]
  end

  defp setup_workflow(%{state: :idle}) do
    [
      %{label: "Next step", value: "Add the EtherCAT Setup smart cell and click Scan Bus."},
      %{
        label: "Why",
        value:
          "The setup smart cell discovers the simulator ring and generates the startup code for a real EtherCAT master session."
      },
      %{
        label: "Main view after setup",
        value: "Use the generated Master render for lifecycle control and current session state."
      }
    ]
  end

  defp setup_workflow(_master) do
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
          "Use it for EtherCAT explanations, WKC/domain context, and the optional loopback playground."
      }
    ]
  end

  defp offline_setup_workflow do
    [
      %{label: "First step", value: "Evaluate the EtherCAT Simulator smart cell."},
      %{
        label: "Then",
        value:
          "Add the EtherCAT Setup smart cell, click Scan Bus, and evaluate the generated code."
      },
      %{
        label: "Main view after setup",
        value: "Use the generated Master render as the primary operational surface."
      }
    ]
  end

  defp playground_rows(info, connections) do
    slaves_by_name = Map.new(Map.get(info, :slaves, []), &{&1.name, &1})
    master_state = master_snapshot().state

    Enum.map(connections, fn %{
                               source: {source_slave, source_signal},
                               target: {target_slave, target_signal}
                             } ->
      source = Map.get(slaves_by_name, source_slave, %{})
      target = Map.get(slaves_by_name, target_slave, %{})
      signal_def = source |> Map.get(:signals, %{}) |> Map.get(source_signal, %{})
      source_value = source |> Map.get(:values, %{}) |> Map.get(source_signal)
      target_value = target |> Map.get(:values, %{}) |> Map.get(target_signal)
      bit_size = Map.get(signal_def, :bit_size, 0)

      %{
        key: "#{source_slave}.#{source_signal}->#{target_slave}.#{target_signal}",
        source_slave: Atom.to_string(source_slave),
        source_signal: Atom.to_string(source_signal),
        target_slave: Atom.to_string(target_slave),
        target_signal: Atom.to_string(target_signal),
        bit_size: bit_size,
        writable:
          Map.get(signal_def, :direction) == :output and bit_size == 1 and master_state == :idle,
        source_value: playground_value(source_value),
        target_value: playground_value(target_value),
        source_on: truthy_signal?(source_value),
        target_on: truthy_signal?(target_value)
      }
    end)
  end

  defp playground_hint([], _master_state) do
    "Optional: auto-wire matching outputs to inputs in the simulator smart cell if you want a tiny loopback exercise before using Setup and Master."
  end

  defp playground_hint(_rows, :idle) do
    "Optional shortcut: toggle one connected output and watch the paired input value. The main path is still Setup -> evaluate generated code -> Master."
  end

  defp playground_hint(_rows, _master_state) do
    "The master now owns cyclic process data, so the playground is read-only. Compare these values with the Master state and domain/WKC information."
  end

  defp master_snapshot do
    state =
      case safe(fn -> EtherCAT.state() end, :idle) do
        value when is_atom(value) -> value
        _ -> :idle
      end

    case first_domain_snapshot() do
      nil ->
        %{state: state, wkc: "n/a", domain_health: "No domains running yet.", domain_state: "n/a"}

      domain ->
        %{
          state: state,
          wkc: domain_wkc(domain),
          domain_health: domain_health(domain),
          domain_state: domain_state(domain)
        }
    end
  end

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

  defp output_refs do
    case Simulator.connections() do
      {:ok, connections} ->
        refs =
          connections
          |> Enum.map(& &1.source)
          |> Enum.uniq()

        if refs == [], do: {:error, :no_outputs}, else: {:ok, refs}

      {:error, :not_found} ->
        {:error, :not_found}

      _ ->
        {:error, :no_outputs}
    end
  end

  defp resolve_slave_name(raw_slave) when is_binary(raw_slave) do
    with {:ok, info} <- Simulator.info(),
         slave when not is_nil(slave) <-
           Enum.find(
             Map.get(info, :slaves, []),
             &(Atom.to_string(&1.name) == String.trim(raw_slave))
           ) do
      {:ok, slave.name}
    else
      _ -> {:error, :invalid_slave}
    end
  end

  defp resolve_slave_name(_raw_slave), do: {:error, :invalid_slave}

  defp resolve_signal_name(raw_signal) when is_binary(raw_signal) do
    trimmed = String.trim(raw_signal)

    if trimmed == "" do
      {:error, :invalid_signal}
    else
      {:ok, String.to_existing_atom(trimmed)}
    end
  rescue
    ArgumentError -> {:error, :invalid_signal}
  end

  defp resolve_signal_name(_raw_signal), do: {:error, :invalid_signal}

  defp parse_bit_value(value) when value in [0, "0", false, "false"], do: {:ok, 0}
  defp parse_bit_value(value) when value in [1, "1", true, "true"], do: {:ok, 1}
  defp parse_bit_value(_value), do: {:error, :invalid_value}

  defp truthy_signal?(value) when value in [1, true], do: true
  defp truthy_signal?(_value), do: false

  defp playground_value(true), do: "1"
  defp playground_value(false), do: "0"
  defp playground_value(nil), do: "nil"
  defp playground_value(value), do: format_value(value)

  defp invoke(fun, success_message) do
    case normalize_invoke_result(safe_invoke(fun), []) do
      :ok -> success_message
      {:error, :not_found} -> error_message("Simulator unavailable.")
      {:error, reason} -> error_message("Teaching action failed: #{inspect(reason)}")
    end
  end

  defp invoke_many(actions, success_message) do
    case Enum.reduce_while(actions, :ok, fn {fun, opts}, :ok ->
           case normalize_invoke_result(safe_invoke(fun), opts) do
             :ok -> {:cont, :ok}
             {:error, reason} -> {:halt, {:error, reason}}
           end
         end) do
      :ok -> success_message
      {:error, :not_found} -> error_message("Simulator unavailable.")
      {:error, reason} -> error_message("Teaching action failed: #{inspect(reason)}")
    end
  end

  defp normalize_invoke_result(:ok, _opts), do: :ok
  defp normalize_invoke_result({:ok, _value}, _opts), do: :ok
  defp normalize_invoke_result({:error, :not_found}, _opts), do: {:error, :not_found}

  defp normalize_invoke_result({:error, reason}, _opts), do: {:error, reason}
  defp normalize_invoke_result(other, _opts), do: {:error, other}

  defp safe_invoke(fun) do
    fun.()
  catch
    :exit, {:noproc, _} -> {:error, :not_found}
    :exit, {:timeout, _} -> {:error, :timeout}
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

  defp info_message(text), do: %{level: "info", text: text}
  defp error_message(text), do: %{level: "error", text: text}

  defp format_value(nil), do: "nil"
  defp format_value(value) when is_binary(value), do: inspect(value)
  defp format_value(value), do: inspect(value, limit: 4, printable_limit: 120)
end
