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
    "Livebook Kino widgets for EtherCAT bus signals — SmartCells for bus setup and " <>
      "visualization, plus LED, switch, and value display widgets."
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib/kino_ethercat* lib/kino_ethercat.ex
           lib/assets/led/build
           lib/assets/setup_cell/build
           lib/assets/switch/build
           lib/assets/value/build
           lib/assets/visualizer_cell/build
           lib/assets/diagnostics/build
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
        Widgets: [
          KinoEtherCAT,
          KinoEtherCAT.LED,
          KinoEtherCAT.Switch,
          KinoEtherCAT.Value,
          KinoEtherCAT.Diagnostics
        ],
        "Smart Cells": [KinoEtherCAT.SetupCell, KinoEtherCAT.VisualizerCell],
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
