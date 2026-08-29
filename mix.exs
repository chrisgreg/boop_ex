defmodule BoopEx.MixProject do
  use Mix.Project

  @version "1.1.0"
  @source_url "https://github.com/chrisgreg/boop_ex"

  def project do
    [
      app: :boop_ex,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Elixir client for Boop, the tiny self-hosted push notification inbox.",
      package: package(),
      docs: docs(),
      name: "BoopEx",
      source_url: @source_url,
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Boop.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:plug, "~> 1.15", only: :test},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url, "Boop" => "https://github.com/chrisgreg/boop"},
      files: ~w(lib mix.exs README.md CHANGELOG.md LICENSE usage-rules.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md", "usage-rules.md"],
      source_ref: "v#{@version}"
    ]
  end
end
