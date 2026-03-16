defmodule KinoEtherCAT do
  @moduledoc """
  Livebook integration for EtherCAT runtime inspection and diagnostics.

  The primary notebook-facing API is centered on renderable runtime resources:

      KinoEtherCAT.master()
      KinoEtherCAT.slave(:io_1)
      KinoEtherCAT.domain(:main)
      KinoEtherCAT.dc()
      KinoEtherCAT.bus()

  Each returns a renderable EtherCAT struct. In Livebook those structs render
  as interactive resource views via `Kino.Render`.

  For live dashboards and signal-oriented widgets, use `KinoEtherCAT.Widgets`.
  For the telemetry dashboard, use `KinoEtherCAT.diagnostics/0` or
  `KinoEtherCAT.Diagnostics.panel/0`. For virtual hardware, use
  `KinoEtherCAT.simulator/0` and `KinoEtherCAT.simulator_faults/0`.
  """

  alias KinoEtherCAT.{Introduction, Runtime, Simulator}

  @spec master() :: %EtherCAT.Master{}
  def master, do: Runtime.master()

  @spec slave(atom()) :: %EtherCAT.Slave{}
  def slave(name), do: Runtime.slave(name)

  @spec domain(atom()) :: %EtherCAT.Domain{}
  def domain(id), do: Runtime.domain(id)

  @spec dc() :: struct()
  def dc, do: Runtime.dc()

  @spec bus() :: KinoEtherCAT.Runtime.BusResource.t()
  def bus, do: Runtime.bus()

  @doc """
  Render the telemetry-driven EtherCAT diagnostic dashboard.
  """
  @spec diagnostics() :: Kino.JS.Live.t()
  def diagnostics, do: KinoEtherCAT.Diagnostics.panel()

  @doc """
  Render the EtherCAT simulator overview panel.
  """
  @spec simulator() :: Kino.JS.Live.t()
  def simulator, do: Simulator.panel()

  @doc """
  Render a simplified simulator-first introduction surface for learning EtherCAT concepts.
  """
  @spec introduction() :: Kino.JS.Live.t()
  def introduction, do: Introduction.panel()

  @doc """
  Render the EtherCAT simulator fault-injection panel.
  """
  @spec simulator_faults() :: Kino.JS.Live.t()
  def simulator_faults, do: Simulator.faults_panel()
end
