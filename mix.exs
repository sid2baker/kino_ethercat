defmodule KinoEtherCAT.MixProject do
  use Mix.Project

  def project do
    [
      app: :kino_ethercat,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      usage_rules: usage_rules()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:kino, "~> 0.18.0"},
      {:ethercat, github: "sid2baker/ethercat"},
      {:usage_rules, "~> 1.1", only: [:dev]}
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
