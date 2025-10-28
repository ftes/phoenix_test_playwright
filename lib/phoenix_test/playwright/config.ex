screenshot_opts_schema = [
  full_page: [type: :boolean, default: true],
  omit_background: [type: :boolean, default: false]
]

browsers = ~w(android chromium electron firefox webkit)a

playwright_recommended_version = "1.55.0"

schema =
  NimbleOptions.new!(
    browser: [
      default: :chromium,
      type: {:in, browsers},
      type_doc: "`#{Enum.map_join(browsers, " | ", &":#{&1}")}`"
    ],
    runner: [
      default: "npx",
      type_spec: quote(do: binary()),
      type_doc: "`t:binary/0`",
      type: {:custom, PhoenixTest.Playwright.Config, :__validate_runner__, []},
      doc:
        "The JS package runner to use to run the Playwright CLI. Accepts either a binary executable exposed in PATH or the absolute path to it."
    ],
    assets_dir: [
      default: "./assets",
      type_spec: quote(do: binary()),
      type_doc: "`t:binary/0`",
      type: {:custom, PhoenixTest.Playwright.Config, :__validate_assets_dir__, []},
      doc:
        "The directory where the JS assets are located and the Playwright CLI is installed.\n" <>
          "Playwright version `#{playwright_recommended_version}` or newer is recommended."
    ],
    cli: [
      type: {:custom, PhoenixTest.Playwright.Config, :__validate_cli__, []},
      deprecated: "Use `assets_dir` instead."
    ],
    executable_path: [
      type: :string,
      doc: "Path to a browser executable to run instead of the bundled one. Use at your own risk."
    ],
    headless: [
      default: true,
      type: :boolean
    ],
    js_logger: [
      default: :default,
      type: {:or, [{:in, [:default, false]}, {:fun, 1}]},
      type_doc: "`:default | false | (msg -> nil)`"
    ],
    screenshot: [
      default: false,
      type: {:or, [:boolean, non_empty_keyword_list: screenshot_opts_schema]},
      type_doc: "`boolean/0 | Keyword.t/0`",
      doc:
        "Either a boolean or a keyword list:\n\n" <>
          NimbleOptions.docs(screenshot_opts_schema, nest_level: 1)
    ],
    screenshot_dir: [
      default: "screenshots",
      type: :string
    ],
    browser_launch_timeout: [
      default: to_timeout(second: 4),
      type: :non_neg_integer
    ],
    timeout: [
      default: to_timeout(second: 2),
      type: :non_neg_integer
    ],
    browser_pool_checkout_timeout: [
      default: to_timeout(minute: 1),
      type: :non_neg_integer
    ],
    browser_pool: [
      default: nil,
      type: :any,
      doc:
        "Reuse a browser from this pool instead of launching a new browser per test suite. See `PhoenixTest.Playwright.BrowserPool`."
    ],
    slow_mo: [
      default: to_timeout(second: 0),
      type: :non_neg_integer
    ],
    trace: [
      default: false,
      type: {:in, [false, true, :open]},
      type_doc: "`boolean/0 | :open`"
    ],
    trace_dir: [
      default: "traces",
      type: :string
    ],
    accept_dialogs: [
      default: true,
      type: :boolean,
      doc: "Accept browser dialogs (`alert()`, `confirm()`, `prompt()`)"
    ],
    browser_context_opts: [
      default: [],
      type: {:or, [:map, :keyword_list]},
      doc:
        "Additional arguments passed to Playwright [Browser.newContext](https://playwright.dev/docs/api/class-browser#browser-new-context).\n" <>
          ~s(E.g. `[http_credentials: %{username: "a", password: "b"}]`)
    ],
    browser_page_opts: [
      default: [],
      type: {:or, [:map, :keyword_list]},
      doc:
        "Additional arguments passed to Playwright [Browser.newPage](https://playwright.dev/docs/api/class-browser#browser-new-page).\n" <>
          ~s(E.g. `[accept_downloads: false]`)
    ],
    selector_engines: [
      default: [],
      type: {:or, [:map, :keyword_list]},
      doc:
        "Define custom Playwright [selector engines](https://playwright.dev/docs/extensibility#custom-selector-engines)."
    ]
  )

setup_all_keys = ~w(browser_pool browser browser_launch_timeout executable_path headless slow_mo)a
setup_keys = ~w(accept_dialogs screenshot trace browser_context_opts browser_page_opts)a

defmodule PhoenixTest.Playwright.Config do
  @moduledoc """
  Configuration options for the Playwright driver.

  Most should be set globally in `config/tests.exs`.
  Some can be overridden per test.

  All options:
  #{NimbleOptions.docs(schema)}

  Options that be overridden per test module via the `use PhoenixTest.Playwright.Case` opts:
  #{Enum.map_join(setup_all_keys, "\n", &"- `:#{&1}`")}

  Options that be overridden per test via ExUnit `@tag`:
  #{Enum.map_join(setup_keys, "\n", &"- `:#{&1}`")}
  """

  @schema schema
  @screenshot_opts_schema screenshot_opts_schema
  @setup_all_keys setup_all_keys
  @setup_keys setup_keys
  @playwright_recommended_version playwright_recommended_version

  def validate!(config) when is_map(config), do: config |> Keyword.new() |> validate!()

  def validate!(config) when is_list(config) do
    global()
    |> Keyword.merge(config)
    |> NimbleOptions.validate!(@schema)
    |> normalize()
  end

  def global do
    :phoenix_test
    |> Application.get_env(:playwright, [])
    |> NimbleOptions.validate!(@schema)
    |> normalize()
  end

  def global(key), do: Keyword.fetch!(global(), key)

  def setup_all_keys, do: @setup_all_keys
  def setup_keys, do: @setup_keys

  defp normalize(config), do: Keyword.new(config, fn {key, value} -> {key, normalize(key, value)} end)

  defp normalize(:screenshot, true), do: NimbleOptions.validate!([], @screenshot_opts_schema)
  defp normalize(_key, value), do: value

  def __validate_runner__(runner) do
    if executable = System.find_executable(runner) do
      {:ok, executable}
    else
      message = """
      could not find runner executable at `#{runner}`.

      To resolve this please
      1. Install a JS package runner like `npx` or `bunx`
      2. Configure the preferred runner in `config/test.exs`, e.g.: `config :phoenix_test, playwright: [runner: "npx"]`
      3. Ensure either the runner is in your PATH or the `runner` value is a absolute path to the executable (e.g. `Path.absname("_build/bun")`)
      """

      {:error, message}
    end
  end

  def __validate_assets_dir__(assets_dir) do
    playwright_json = Path.join([assets_dir, "node_modules", "playwright", "package.json"])

    with {:ok, string} <- File.read(playwright_json),
         {:ok, json} <- JSON.decode(string) do
      version = json["version"] || "0"

      if Version.compare(version, @playwright_recommended_version) == :lt do
        IO.warn("Playwright version #{version} is below recommended #{@playwright_recommended_version}")
      end

      {:ok, assets_dir}
    else
      {:error, error} ->
        message = """
        could not find playwright in `#{assets_dir}`.
        Reason: #{inspect(error)}

        To resolve this please
        1. Install playwright, e.g. via `npm --prefix assets install playwright`
        """

        {:error, message}
    end
  end

  def __validate_cli__(_cli) do
    {:error,
     "it is deprecated. Use `assets_dir` instead if you want to customize the Playwright installation directory path and remove the `cli` option."}
  end
end
