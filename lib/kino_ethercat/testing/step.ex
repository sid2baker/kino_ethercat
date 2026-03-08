defmodule KinoEtherCAT.Testing.Step do
  @moduledoc false

  @enforce_keys [:title, :kind]
  defstruct [:title, :kind, params: %{}]

  @type kind :: :wait | :write_output | :expect_input | :expect_slave_state

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
end
