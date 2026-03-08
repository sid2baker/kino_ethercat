defmodule KinoEtherCAT.Testing.Step do
  @moduledoc false

  @enforce_keys [:title, :kind]
  defstruct [:title, :kind, params: %{}]

  @type kind ::
          :wait
          | :manual
          | :write_output
          | :expect_input
          | :expect_slave_state
          | :stop_domain_cycling
          | :start_domain_cycling
          | :expect_dc_lock

  @type t :: %__MODULE__{
          title: String.t(),
          kind: kind(),
          params: map()
        }

  @spec wait(String.t(), non_neg_integer(), keyword()) :: t()
  def wait(title, duration_ms, _opts \\ []) do
    %__MODULE__{
      title: title,
      kind: :wait,
      params: %{duration_ms: duration_ms}
    }
  end

  @spec manual(String.t(), String.t(), keyword()) :: t()
  def manual(title, instruction, opts \\ []) do
    %__MODULE__{
      title: title,
      kind: :manual,
      params: %{
        instruction: instruction,
        continue_label: Keyword.get(opts, :continue_label, "Continue"),
        acknowledged_detail: Keyword.get(opts, :acknowledged_detail, "continued by operator")
      }
    }
  end

  @spec write_output(String.t(), atom(), atom(), term(), keyword()) :: t()
  def write_output(title, slave, signal, value, _opts \\ []) do
    %__MODULE__{
      title: title,
      kind: :write_output,
      params: %{slave: slave, signal: signal, value: value}
    }
  end

  @spec expect_input(String.t(), atom(), atom(), term(), keyword()) :: t()
  def expect_input(title, slave, signal, expected, opts \\ []) do
    %__MODULE__{
      title: title,
      kind: :expect_input,
      params: %{
        slave: slave,
        signal: signal,
        expected: expected,
        within_ms: Keyword.get(opts, :within_ms, 1_000),
        poll_ms: Keyword.get(opts, :poll_ms, 20)
      }
    }
  end

  @spec expect_slave_state(String.t(), atom(), atom(), keyword()) :: t()
  def expect_slave_state(title, slave, expected_state, opts \\ []) do
    %__MODULE__{
      title: title,
      kind: :expect_slave_state,
      params: %{
        slave: slave,
        expected_state: expected_state,
        within_ms: Keyword.get(opts, :within_ms, 1_000),
        poll_ms: Keyword.get(opts, :poll_ms, 20)
      }
    }
  end

  @spec stop_domain_cycling(String.t(), atom(), keyword()) :: t()
  def stop_domain_cycling(title, domain_id, _opts \\ []) do
    %__MODULE__{
      title: title,
      kind: :stop_domain_cycling,
      params: %{domain_id: domain_id}
    }
  end

  @spec start_domain_cycling(String.t(), atom(), keyword()) :: t()
  def start_domain_cycling(title, domain_id, _opts \\ []) do
    %__MODULE__{
      title: title,
      kind: :start_domain_cycling,
      params: %{domain_id: domain_id}
    }
  end

  @spec expect_dc_lock(String.t(), atom(), keyword()) :: t()
  def expect_dc_lock(title, expected_state, opts \\ []) do
    %__MODULE__{
      title: title,
      kind: :expect_dc_lock,
      params: %{
        expected_state: expected_state,
        within_ms: Keyword.get(opts, :within_ms, 5_000),
        poll_ms: Keyword.get(opts, :poll_ms, 50)
      }
    }
  end
end
