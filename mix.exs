defmodule PhoenixTestPlaywright.MixProject do
  use Mix.Project

  @version "0.20.0-rc.0"
  @source_url "https://github.com/ftes/phoenix_test_playwright"
  @description """
  Execute PhoenixTest cases in an actual browser via Playwright.
  """

  def project do
    [
      app: :phoenix_test_playwright,
      version: @version,
      description: @description,
      elixir: "~> 1.18",
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      package: package(),
      dialyzer: [
        plt_local_path: "priv/plts/project.plt",
        plt_core_path: "priv/plts/core.plt",
        plt_add_apps: [:ex_unit, :mix, :phoenix_test]
      ],
      name: "PhoenixTestPlaywright",
      source_url: @source_url,
      docs: docs(),
      aliases: aliases(),
      usage_rules: usage_rules()
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
      {:esbuild, ">= 0.9.0 and < 1.0.0", only: :test, runtime: false},
      {:ex_doc, ">= 0.37.0 and < 1.0.0", only: :dev, runtime: false},
      {:phoenix, "~> 1.7"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_test, ">= 0.12.0 and < 1.0.0", runtime: false},
      {:plug_cowboy, "~> 2.7", only: :test, runtime: false},
      {:phoenix_ecto, "~> 4.5", optional: true},
      {:ecto_sql, "~> 3.10", optional: true},
      {:postgrex, ">= 0.0.0", only: :test},
      {:testcontainers, "~> 2.0", only: :test},
      {:usage_rules, "~> 1.3", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:styler, "~> 1.3", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:makeup_diff, ">= 0.1.0 and < 1.0.0", only: :dev},
      {:nimble_options, "~> 1.1"},
      {:playwright_ex, "~> 0.17.0-rc.4"}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp package do
    [
      licenses: ["MIT"],
      links: %{"Github" => @source_url},
      files: ~w(lib .formatter.exs mix.exs README* LICENSE* CHANGELOG* usage-rules.md),
      exclude_patterns: ~w(priv/static/assets priv/plts)
    ]
  end

  def cli do
    [
      preferred_envs: [
        format: :test,
        setup: :test,
        check: :test,
        "assets.setup": :test,
        "assets.setup.playwright": :test,
        "assets.build": :test,
        esbuild: :test,
        "esbuild.install": :test,
        "test.websocket": :test
      ]
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: [
        "README.md": [title: "Overview"],
        "CHANGELOG.md": [title: "Changelog"]
      ],
      nest_modules_by_prefix: [PhoenixTest.Playwright],
      filter_modules: fn _, metadata -> not String.contains?(to_string(metadata.source_path), "/internal/") end
    ]
  end

  # `mix usage_rules.sync --yes` rewrites the managed block of AGENTS.md from this list.
  defp usage_rules do
    [
      file: "AGENTS.md",
      usage_rules: [
        {:usage_rules, sub_rules: []},
        {:playwright_ex, link: :markdown}
      ]
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.setup.playwright", "playwright.source", "assets.build", "ecto.create"],
      "assets.setup": [
        "esbuild.install --if-missing"
      ],
      "assets.setup.playwright": "playwright_ex.install -- chromium firefox --with-deps --only-shell",
      "assets.build": ["esbuild default"],
      "playwright.source": &playwright_source/1,
      "test.websocket": "phoenix_test_playwright.test.websocket",
      check: [
        "format --check-formatted",
        "credo",
        "compile --warnings-as-errors",
        "usage_rules.sync --check",
        "dialyzer --format github --format dialyxir",
        "assets.build",
        "test --warnings-as-errors"
      ]
    ]
  end

  @playwright_paths ~w(
    packages/playwright-core/src packages/injected/src packages/isomorphic packages/protocol
    packages/utils packages/playwright/src/matchers docs/src/api tests/page tests/library
  )

  # Playwright's source at the driver version PlaywrightEx pins, for agents to read: shallow,
  # blobless and sparse, in gitignored tmp/.
  defp playwright_source(_args) do
    Mix.Task.run("loadpaths")
    version = PlaywrightEx.Driver.version()
    dir = "tmp/playwright-#{version}"

    if not File.dir?(dir) do
      # Into a temporary directory first, so an interrupted clone isn't taken for a finished one.
      tmp = dir <> ".tmp"
      File.rm_rf!(tmp)

      git!(
        ~w(clone --depth 1 --filter=blob:none --sparse --branch v#{version} https://github.com/microsoft/playwright #{tmp})
      )

      git!(["-C", tmp, "sparse-checkout", "set" | @playwright_paths])
      File.rename!(tmp, dir)
    end

    Mix.shell().info("Playwright #{version} source: #{dir}")
  end

  defp git!(args) do
    {output, status} = System.cmd("git", args, stderr_to_stdout: true)
    if status != 0, do: Mix.raise("git #{Enum.join(args, " ")} exited with #{status}:\n#{output}")
  end
end
