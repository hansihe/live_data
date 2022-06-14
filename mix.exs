defmodule LiveData.MixProject do
  use Mix.Project

  def project do
    [
      app: :live_data,
      version: "0.1.0-alpha1",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      docs: docs(),
      description: """
      LiveView-like experience for JSON endpoints
      """
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
      {:phoenix, "~> 1.5.8"},
      {:jason, "~> 1.2"},

      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      main: "LiveData",
      source_url: "https://github.com/hansihe/live_data",
      extra_section: "GUIDES",
      extras: extras(),
      groups_for_extras: groups_for_extras(),
      groups_for_modules: groups_for_modules()
    ]
  end

  defp extras do
    [
      "guides/introduction/installation.md"
    ]
  end

  defp groups_for_extras do
    [
      Introduction: ~r/guides\/introduction\/.?/
    ]
  end

  defp groups_for_modules do
    # Ungrouped modules:
    #
    # LiveData
    # LiveData.Router
    # LiveData.Tracked

    [
      "Data-structures": [
        LiveData.Tracked.CustomFragment,
        LiveData.Tracked.Datastructures.ClientList
      ],
      Encodings: [
        LiveData.Tracked.Encoding.JSON,
        LiveData.Tracked.Encoding.Binary
      ]
    ]
  end

  defp package do
    [
      maintainers: ["Hans Elias B. Josephsen"],
      licenses: ["MIT"],
      links: %{
        GitHub: "https://github.com/hansihe/live_data"
      }
    ]
  end
end
