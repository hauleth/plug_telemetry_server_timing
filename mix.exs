defmodule PlugServerTiming.MixProject do
  use Mix.Project

  def project do
    [
      app: :plug_server_timing,
      version: "0.1.0",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: [
        assets: "assets/",
        extras: ["README.md"],
        main: "readme"
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application, do: []

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:telemetry, "~> 0.4.0"},
      {:plug, "~> 1.0"},

      {:ex_doc, ">= 0.0.0", only: [:dev]}
    ]
  end
end
