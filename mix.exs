defmodule KinoEtherCAT.MixProject do
  use Mix.Project

  @version "0.2.0-dev"
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
      {:ethercat, github: "sid2baker/ethercat"},
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
           lib/assets/slave_panel/build
           lib/assets/switch/build
           lib/assets/value/build
           lib/assets/visualizer_cell/build
           lib/assets/diagnostics/build
           lib/assets/testing/build
           mix.exs README.md LICENSE CHANGELOG.md usage-rules.md)
    ]
  end

  defp docs do
    [
      main: "KinoEtherCAT",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: ["README.md", "CHANGELOG.md", "LICENSE"],
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
        Testing: [
          KinoEtherCAT.Testing,
          KinoEtherCAT.Testing.Scenario,
          KinoEtherCAT.Testing.Step,
          KinoEtherCAT.Testing.Run,
          KinoEtherCAT.Testing.Report,
          KinoEtherCAT.Testing.Scenarios,
          KinoEtherCAT.Testing.Scenarios.LoopbackSmoke,
          KinoEtherCAT.Testing.Scenarios.DCLock,
          KinoEtherCAT.Testing.Scenarios.WatchdogRecovery
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
          KinoEtherCAT.SmartCells.Visualizer,
          KinoEtherCAT.SmartCells.SDOExplorer,
          KinoEtherCAT.SmartCells.RegisterExplorer,
          KinoEtherCAT.SmartCells.SIIExplorer
        ],
        Drivers: [
          KinoEtherCAT.Driver,
          KinoEtherCAT.Driver.EL1809,
          KinoEtherCAT.Driver.EL2809,
          KinoEtherCAT.Driver.EL3202
        ]
      ]
    ]
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
