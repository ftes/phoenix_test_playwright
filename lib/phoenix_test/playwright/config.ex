browsers = ~w(chromium firefox webkit)a

# styler:sort
browser_opts = [
  browser: [
    type: {:in, browsers},
    type_doc: "`#{Enum.map_join(browsers, " | ", &":#{&1}")}`",
    doc: "Defaults to `config :playwright_ex, :test, browser_name: ...` (`:chromium`)."
  ],
  browser_launch_opts: [
    type: :keyword_list,
    doc: """
    Additional arguments passed to Playwright [browserType.launch](https://playwright.dev/docs/api/class-browsertype#browser-type-launch),
    merged over `config :playwright_ex, :test, launch_options: ...`.
    E.g. `[args: ["--use-fake-ui-for-media-stream", "--use-fake-device-for-media-stream"]]`.
    Can't be used with remote browser (ws_endpoint).
    """
  ],
  browser_launch_timeout: [
    type: :timeout,
    doc: "Timeout in milliseconds. `:infinity` disables the timeout. Shorthand for `browser_launch_opts: [timeout: ...]`."
  ],
  executable_path: [
    type: :string,
    doc: """
    Path to a browser executable to run instead of the bundled one.
    Use at your own risk. Shorthand for `browser_launch_opts: [executable_path: ...]`.
    """
  ],
  headless: [
    type: :boolean,
    doc: "Shorthand for `browser_launch_opts: [headless: ...]`."
  ],
  slow_mo: [
    type: :non_neg_integer,
    doc: "Shorthand for `browser_launch_opts: [slow_mo: ...]`."
  ]
]

# styler:sort
schema_opts = [
  accept_dialogs: [
    default: true,
    type: :boolean,
    doc: "Accept browser dialogs (`alert()`, `confirm()`, `prompt()`)."
  ],
  browser: browser_opts[:browser],
  browser_context_opts: [
    default: [],
    type: {:or, [{:map, :atom, :any}, :keyword_list]},
    doc: """
    Additional arguments passed to Playwright [Browser.newContext](https://playwright.dev/docs/api/class-browser#browser-new-context).
    E.g. `[http_credentials: %{username: "a", password: "b"}]`.
    """
  ],
  browser_launch_opts: browser_opts[:browser_launch_opts],
  browser_launch_timeout: browser_opts[:browser_launch_timeout],
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
  executable_path: browser_opts[:executable_path],
  headless: browser_opts[:headless],
  js_logger: [
    default: PhoenixTest.Playwright.JsLogger,
    type: :atom,
    type_doc: "`module | nil`",
    doc: "`nil` to disable, or a module that implements the `PhoenixTest.Playwright.JsLogger` behaviour."
  ],
  screenshot_dir: [
    default: "screenshots",
    type: :string,
    doc:
      "Directory where `screenshot/3` saves files. See also `:snapshot_dir` for `assert_screenshot/3` reference images."
  ],
  selector_engines: [
    default: [],
    type: {:or, [:map, :keyword_list]},
    doc: """
    Define custom Playwright [selector engines](https://playwright.dev/docs/extensibility#custom-selector-engines).
    """
  ],
  slow_mo: browser_opts[:slow_mo],
  snapshot_dir: [
    default: "test/snapshots",
    type: :string,
    doc: """
    Directory where `assert_screenshot/3` reads and writes baseline images.

    Diff images on mismatch are written to `<snapshot_dir>/__diff__/`. Add that subdirectory to `.gitignore`:

    ```
    **/__diff__/
    ```
    """
  ],
  timeout: [
    default: to_timeout(second: 2),
    type: :timeout,
    doc: """
    Default maximum time for a single browser operation, such as an action, assertion or navigation.
    Many operations accept a `timeout:` option to override it.
    Also bounds closing browser contexts and pooled browsers. See [Timeouts](#module-timeouts).
    """
  ],
  ws_endpoint: [
    type: :string,
    doc: """
    WebSocket endpoint URL for connecting to a remote Playwright server.
    If provided, browsers run on that server instead of being launched locally.
    The connection goes through a local Playwright driver that PlaywrightEx downloads on first use.
    Example: "ws://localhost:3000"

    This is useful for:
    - Containers without browser system dependencies
    - Containerized CI environments with a separate Playwright server
    - Connecting to remote/shared Playwright instances
    """
  ]
]

schema = NimbleOptions.new!(schema_opts)

setup_all_keys = ~w(browser_pool browser browser_launch_opts browser_launch_timeout executable_path headless slow_mo)a
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
        trace: :retain_on_failure,
        screenshot: :only_on_failure

  The browser options above are merged over it.

  ## Timeouts

  Timeouts are in milliseconds, or `:infinity` to disable them. `0` means no waiting.
  This applies to `timeout`, `browser_launch_timeout`,
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
