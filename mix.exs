defmodule KinoEtherCAT.MixProject do
  use Mix.Project

  @version "0.3.1"
  @source_url "https://github.com/sid2baker/kino_ethercat"

  def project do
    [
      app: :kino_ethercat,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      deps: deps(),
      docs: docs(),
      source_url: @source_url,
      usage_rules: usage_rules()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {KinoEtherCAT.Application, []}
    ]
  end

  defp deps do
    [
      {:kino, "~> 0.18"},
      ethercat_dep(),
      {:ex_doc, "~> 0.36", only: :dev, runtime: false},
      {:usage_rules, "~> 1.1", only: [:dev]}
    ]
  end

  defp description do
    "Livebook tools for EtherCAT discovery, runtime inspection, control, and diagnostics."
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib/kino_ethercat* lib/kino_ethercat.ex
           lib/assets/led/build
           lib/assets/explorer_cell/build
           lib/assets/runtime_panel/build
           lib/assets/setup_cell/build
           lib/assets/simulator_cell/build
           lib/assets/simulator_panel/build
           lib/assets/slave_panel/build
           lib/assets/switch/build
           lib/assets/value/build
           lib/assets/visualizer_cell/build
           lib/assets/diagnostics/build
           lib/assets/introduction_panel/build
           lib/assets/simulator_faults_panel/build
           examples
           mix.exs README.md LICENSE CHANGELOG.md RELEASE.md usage-rules.md)
    ]
  end

  defp docs do
    [
      main: "KinoEtherCAT",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: [
        "README.md",
        "examples/README.md",
        "examples/01_ethercat_introduction.livemd",
        "CHANGELOG.md",
        "LICENSE"
      ],
      groups_for_modules: [
        Runtime: [
          KinoEtherCAT,
          KinoEtherCAT.Diagnostics,
          KinoEtherCAT.Diagnostics.Panel,
          KinoEtherCAT.Runtime,
          KinoEtherCAT.Runtime.Master,
          KinoEtherCAT.Runtime.Slave,
          KinoEtherCAT.Runtime.Domain,
          KinoEtherCAT.Runtime.Bus,
          KinoEtherCAT.Runtime.DC
        ],
        Teaching: [
          KinoEtherCAT.Introduction,
          KinoEtherCAT.Introduction.Panel,
          KinoEtherCAT.Introduction.View
        ],
        Simulator: [
          KinoEtherCAT.Simulator,
          KinoEtherCAT.Simulator.Panel,
          KinoEtherCAT.Simulator.View,
          KinoEtherCAT.Simulator.Snapshot,
          KinoEtherCAT.Simulator.FaultsPanel,
          KinoEtherCAT.Simulator.FaultsView
        ],
        Widgets: [
          KinoEtherCAT.Widgets,
          KinoEtherCAT.Widgets.LED,
          KinoEtherCAT.Widgets.Switch,
          KinoEtherCAT.Widgets.Value,
          KinoEtherCAT.Widgets.SlavePanel
        ],
        "Smart Cells": [
          KinoEtherCAT.SmartCells.Setup,
          KinoEtherCAT.SmartCells.Simulator,
          KinoEtherCAT.SmartCells.Visualizer,
          KinoEtherCAT.SmartCells.SlaveExplorer,
          KinoEtherCAT.SmartCells.RegisterExplorer,
          KinoEtherCAT.SmartCells.SDOExplorer,
          KinoEtherCAT.SmartCells.SIIExplorer
        ],
        Drivers: [
          KinoEtherCAT.Driver,
          KinoEtherCAT.Driver.EK1100,
          KinoEtherCAT.Driver.EL1809,
          KinoEtherCAT.Driver.EL2809,
          KinoEtherCAT.Driver.EL3202
        ]
      ]
    ]
  end

  defp ethercat_dep do
    case System.get_env("KINO_ETHERCAT_USE_LOCAL_ETHERCAT") do
      value when value in ["1", "true", "TRUE"] ->
        {:ethercat, path: "../ethercat"}

      _ ->
        {:ethercat, "~> 0.3.0"}
    end
  end

  defp usage_rules do
    [
      file: "AGENTS.md",
      usage_rules: [:elixir, :otp],
      skills: [
        build: [
          "elixir-otp": [
            description:
              "Use this skill when working with standard Elixir and OTP — GenServer, supervisors, processes, streams, pattern matching, etc.",
            usage_rules: [:usage_rules]
          ]
        ]
      ]
    ]
  end
end
