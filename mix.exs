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
      ],
      Internal: [
        LiveData.Tracked.FlatAst,
        LiveData.Tracked.FlatAst.FromAst,
        LiveData.Tracked.FlatAst.ToAst,
        LiveData.Tracked.FlatAst.Expr.Scope,
        LiveData.Tracked.FlatAst.Expr.Block,
        LiveData.Tracked.FlatAst.Expr.AccessField,
        LiveData.Tracked.FlatAst.Expr.CallMF,
        LiveData.Tracked.FlatAst.Pass.Normalize,
        LiveData.Tracked.FlatAst.Pass.CalculateNesting,
        LiveData.Tracked.FlatAst.Pass.RewriteAst,
        LiveData.Tracked.FlatAst.Pass.RewriteAst.MakeStructure,
        LiveData.Tracked.FlatAst.Pass.RewriteAst.ExpandDependencies,
        LiveData.Tracked.FlatAst.Pass.RewriteAst.RewriteScope,
        LiveData.Tracked.FlatAst.Pass.RewriteAst.StaticsAgent,
        LiveData.Tracked.FlatAst.PDAst,
        LiveData.Tracked.FlatAst.Util.Transcribe,
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
