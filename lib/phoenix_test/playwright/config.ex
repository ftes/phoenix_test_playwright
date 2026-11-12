browsers = ~w(chromium firefox webkit)a

# styler:sort
schema_opts = [
  accept_dialogs: [
    default: true,
    type: :boolean,
    doc: "Accept browser dialogs (`alert()`, `confirm()`, `prompt()`)."
  ],
  browser: [
    type: {:in, browsers},
    type_doc: "`#{Enum.map_join(browsers, " | ", &":#{&1}")}`",
    doc: "Defaults to `config :playwright_ex, :test, browser_name: ...` (`:chromium`)."
  ],
  browser_context_opts: [
    default: [],
    type: {:or, [{:map, :atom, :any}, :keyword_list]},
    doc: """
    Additional arguments passed to Playwright [Browser.newContext](https://playwright.dev/docs/api/class-browser#browser-new-context)
    for a test module or test, e.g. `@tag browser_context_opts: [http_credentials: %{username: "a", password: "b"}]`.
    They win over `config :playwright_ex, :test, context_options: ...`, which is the place for global context options.
    """
  ],
  browser_launch_opts: [
    type: :keyword_list,
    doc: """
    Arguments passed to Playwright [browserType.launch](https://playwright.dev/docs/api/class-browsertype#browser-type-launch)
    for a test module, merged one level deep over `config :playwright_ex, :test, launch_options: ...`,
    which is the place for global launch options.
    E.g. `use PhoenixTest.Playwright.Case, browser_launch_opts: [headless: false, slow_mo: 500]`.
    """
  ],
  browser_pool: [
    type: {:in, [:shared, :exclusive]},
    type_doc: "`:shared | :exclusive`",
    doc: """
    How to get a browser from `PlaywrightEx.Test.BrowserPool`:
    `:shared` (one browser for all test modules at once) or
    `:exclusive` (one browser per test module, at most `config :playwright_ex, :test, workers: ...` at once).
    Defaults to `:exclusive` for Firefox and `:shared` otherwise.
    """
  ],
  ecto_sandbox_stop_owner_delay: [
    default: 0,
    type: :non_neg_integer,
    doc: """
    Delay in milliseconds before shutting down the Ecto sandbox owner after a
    test ends. Use this to allow LiveViews and other processes in your app
    time to stop using database connections before the sandbox owner is
    terminated.
    """
  ],
  js_logger: [
    default: PhoenixTest.Playwright.JsLogger,
    type: :atom,
    type_doc: "`module | nil`",
    doc: "`nil` to disable, or a module that implements the `PhoenixTest.Playwright.JsLogger` behaviour."
  ],
  selector_engines: [
    default: [],
    type: {:or, [:map, :keyword_list]},
    doc: """
    Define custom Playwright [selector engines](https://playwright.dev/docs/extensibility#custom-selector-engines).
    """
  ],
  timeout: [
    default: to_timeout(second: 2),
    type: :timeout,
    doc: """
    Default maximum time for a single browser operation, such as an action, assertion or navigation.
    Many operations accept a `timeout:` option to override it.
    Also bounds closing browser contexts. See [Timeouts](#module-timeouts).
    """
  ]
]

schema = NimbleOptions.new!(schema_opts)

setup_all_keys = ~w(browser_pool browser browser_launch_opts)a
setup_keys = ~w(accept_dialogs ecto_sandbox_stop_owner_delay browser_context_opts)a

defmodule PhoenixTest.Playwright.Config do
  @moduledoc """
  Configuration options for the Playwright driver.

  Most should be set globally in `config/test.exs`.
  Some can be overridden per test.

  All options:
  #{NimbleOptions.docs(schema)}

  Options that can be overridden per test module via the `use PhoenixTest.Playwright.Case` opts:
  #{Enum.map_join(setup_all_keys, "\n", &"- `:#{&1}`")}

  Options that can be overridden per test via ExUnit `@tag`:
  #{Enum.map_join(setup_keys, "\n", &"- `:#{&1}`")}

  ## PlaywrightEx options

  Browsers come from `PlaywrightEx.Test.BrowserPool`, and each test is registered with
  `PlaywrightEx.Test`. So `config :playwright_ex, :test` applies too, e.g. for
  traces, screenshots and videos (also as `@tag trace: :on`), `workers` and `output_dir`:

      config :playwright_ex, :test,
        browser_name: :chromium,
        launch_options: [headless: false, slow_mo: 500],
        context_options: [locale: "de-DE"],
        trace: :retain_on_failure,
        screenshot: :only_on_failure

  It also resolves `assert_screenshot/3` baselines (`snapshot_dir`, `snapshot_path_template`).
  `browser_launch_opts` and `browser_context_opts` are merged over its `launch_options` and `context_options`.

  ## Timeouts

  Timeouts are in milliseconds, or `:infinity` to disable them. `0` means no waiting.
  This applies to `timeout`
  and the `timeout:` option of individual operations.
  ExUnit's own test timeout (see `ExUnit.configure/1`) still applies.
  """

  @schema schema
  @setup_all_keys setup_all_keys
  @setup_keys setup_keys

  @doc false
  # A timeout of 0 means "don't wait" here, but "wait forever" to Playwright.
  def driver_timeout(0), do: 1
  def driver_timeout(timeout), do: timeout

  @doc false
  # Playwright calls that take no timeout are bounded by the caller, with grace for a busy driver.
  def client_timeout(:infinity), do: :infinity
  def client_timeout(timeout), do: max(to_timeout(second: 1), round(timeout * 1.5))

  @doc false
  def validate!(config) when is_map(config), do: config |> Keyword.new() |> validate!()

  def validate!(config) when is_list(config) do
    global()
    |> Keyword.merge(config)
    |> NimbleOptions.validate!(@schema)
    |> normalize()
  end

  @doc false
  def global do
    :phoenix_test
    |> Application.get_env(:playwright, [])
    |> NimbleOptions.validate!(@schema)
    |> normalize()
  end

  def global(key), do: Keyword.fetch!(global(), key)

  @doc false
  def setup_all_keys, do: @setup_all_keys

  @doc false
  def setup_keys, do: @setup_keys

  defp normalize(config), do: Keyword.new(config, fn {key, value} -> {key, normalize(key, value)} end)

  defp normalize(:browser_context_opts, value), do: Keyword.new(value)
  defp normalize(_key, value), do: value
end
