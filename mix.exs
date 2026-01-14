defmodule PhoenixTestPlaywright.MixProject do
  use Mix.Project

  @version "0.10.0"
  @source_url "https://github.com/ftes/phoenix_test_playwright"
  @description """
  Execute PhoenixTest cases in an actual browser via Playwright.
  """

  def project do
    [
      app: :phoenix_test_playwright,
      version: @version,
      description: @description,
      elixir: "~> 1.15",
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      package: package(),
      name: "PhoenixTestPlaywright",
      source_url: @source_url,
      docs: docs(),
      aliases: aliases()
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
      {:esbuild, "~> 0.9", only: :test, runtime: false},
      {:ex_doc, "~> 0.37", only: :dev, runtime: false},
      {:phoenix, "~> 1.7"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_test, "~> 0.8", runtime: false},
      {:plug_cowboy, "~> 2.7", only: :test, runtime: false},
      {:phoenix_ecto, "~> 4.5", optional: true},
      {:ecto_sql, "~> 3.10", optional: true},
      {:postgrex, ">= 0.0.0", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:styler, "~> 1.3", only: [:dev, :test], runtime: false},
      {:makeup_diff, "~> 0.1", only: :dev},
      {:nimble_options, "~> 1.1"},
      # {:playwright_ex, "~> 0.3"}
      {:playwright_ex, github: "ftes/playwright_ex", ref: "545bc4d"}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp package do
    [
      licenses: ["MIT"],
      links: %{"Github" => @source_url},
      exclude_patterns: ~w(assets/node_modules priv/static/assets)
    ]
  end

  def cli do
    [
      preferred_envs: [
        format: :test,
        setup: :test,
        check: :test,
        "assets.setup": :test,
        "assets.build": :test,
        esbuild: :test,
        "esbuild.install": :test
      ]
    ]
  end

  defp docs do
    [
      main: "PhoenixTest.Playwright",
      source_ref: "v#{@version}",
      extras: [
        "CHANGELOG.md": [title: "Changelog"]
      ],
      nest_modules_by_prefix: [PhoenixTest.Playwright],
      filter_modules: fn _, metadata -> not String.contains?(to_string(metadata.source_path), "/internal/") end
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build", "ecto.create"],
      "assets.setup": [
        "esbuild.install --if-missing",
        "cmd npm install --prefix priv/static/assets",
        "cmd npm exec --prefix priv/static/assets playwright -- install chromium --with-deps --only-shell",
        "cmd npm exec --prefix priv/static/assets playwright -- install firefox --with-deps --only-shell"
      ],
      "assets.build": ["esbuild default"],
      check: [
        "format --check-formatted",
        "credo",
        "compile --warnings-as-errors",
        "assets.build",
        "test --warnings-as-errors"
      ]
    ]
  end
end
