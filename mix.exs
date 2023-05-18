defmodule TeslaCurl.MixProject do
  use Mix.Project

  @project_url "https://github.com/colincromar/tesla_curl"

  def project do
    [
      app: :tesla_curl,
      deps: deps(),
      docs: [
        main: "readme",
        api_reference: false,
        extras: ["README.md"],
        extra_section: []
      ],
      description: "A middleware for the Tesla HTTP client that logs requests expressed in Curl",
      dialyzer: dialyzer(),
      elixir: "~> 1.14",
      name: "TeslaCurl",
      package: package(),
      project_url: @project_url,
      start_permanent: Mix.env() == :prod,
      source_url: @project_url,
      version: "1.2.0"
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false},
      {:ex_doc, ">= 0.0.0", only: [:dev], runtime: false},
      {:tesla, "~> 1.4"}
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:mix],
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
    ]
  end

  defp package do
    [
      maintainers: ["Colin Cromar"],
      licenses: ["MIT"],
      links: %{"GitHub" => @project_url}
    ]
  end
end
