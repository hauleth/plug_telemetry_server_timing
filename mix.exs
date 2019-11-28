defmodule PlugServerTiming.MixProject do
  use Mix.Project

  def project do
    ver = version()
    [
      app: :plug_telemetry_server_timing,
      version: ver,
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
        source_ref: ver,
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

  defp version do
    with :error <- hex_version(),
         :error <- git_version()
    do
      "0.0.0-dev"
    else
      {:ok, ver} -> ver
    end
  end

  defp hex_version do
    with {:ok, terms} <- :file.consult("hex_metadata.config") do
      Keyword.fetch(terms, :version)
    else
      _ -> :error
    end
  end

  defp git_version do
    System.cmd("git", ~w[describe])
  else
    {0, ver} -> {:ok, String.trim(ver)}
    _ -> :error
  catch
    _, _ -> :error
  end
end
