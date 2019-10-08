defmodule PlugServerTiming.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :plug_telemetry_server_timing,
      version: @version,
      description: "Plug for providing Telemetry metrics within browser DevTools",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      source_url: "https://github.com/hauleth/plug_telemetry_server_timing",
      docs: [
        assets: "assets/",
        extras: ["README.md"],
        main: "readme"
      ],
      package: [
        source_ref: @version,
        licenses: ["MIT"],
        links: %{
          "GitHub" => "https://github.com/hauleth/plug_telemetry_server_timing"
        }
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
      {:ex_doc, ">= 0.0.0", only: [:dev]},
      {:credo, ">= 0.0.0", only: [:dev]}
    ]
  end
end
