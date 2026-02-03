screenshot_opts_schema = [
  full_page: [type: :boolean, default: true],
  omit_background: [type: :boolean, default: false]
]

browsers = ~w(android chromium electron firefox webkit)a

# styler:sort
browser_opts = [
  browser: [
    default: :chromium,
    type: {:in, browsers},
    type_doc: "`#{Enum.map_join(browsers, " | ", &":#{&1}")}`"
  ],
  browser_launch_timeout: [
    default: to_timeout(second: 4),
    type: :non_neg_integer
  ],
  executable_path: [
    type: :string,
    doc: """
    Path to a browser executable to run instead of the bundled one.
    Use at your own risk.
    """
  ],
  headless: [
    default: true,
    type: :boolean
  ],
  slow_mo: [
    default: to_timeout(second: 0),
    type: :non_neg_integer
  ]
]

browser_pool_opts =
  [
    id: [required: true, type: :atom],
    size: [required: false, type: :integer, doc: "The default value is `System.schedulers_online() / 2`."]
  ] ++ browser_opts

playwright_recommended_version = "1.55.0"

# styler:sort
schema_opts = [
  accept_dialogs: [
    default: true,
    type: :boolean,
    doc: "Accept browser dialogs (`alert()`, `confirm()`, `prompt()`)."
  ],
  assets_dir: [
    default: "./assets",
    type_spec: quote(do: binary()),
    type_doc: "`t:binary/0`",
    type: {:custom, PhoenixTest.Playwright.Config, :__validate_assets_dir__, []},
    doc: """
    The directory where the JS assets are located and the Playwright CLI is installed.
    Playwright version `#{playwright_recommended_version}` or newer is recommended.
    Alternatively, use `ws_endpoint` to connect to a remote Playwright server instead, in which case no local node and playwright is required and `assets_dir` is ignored.
    """
  ],
  browser: browser_opts[:browser],
  browser_context_opts: [
    default: [],
    type: {:or, [:map, :keyword_list]},
    doc: """
    Additional arguments passed to Playwright [Browser.newContext](https://playwright.dev/docs/api/class-browser#browser-new-context).
    E.g. `[http_credentials: %{username: "a", password: "b"}]`.
    """
  ],
  browser_launch_timeout: browser_opts[:browser_launch_timeout],
  browser_page_opts: [
    default: [],
    type: {:or, [:map, :keyword_list]},
    doc: """
    Additional arguments passed to Playwright [Browser.newPage](https://playwright.dev/docs/api/class-browser#browser-new-page).
    (E.g. `[accept_downloads: false]`.
    """
  ],
  browser_pool: [
    default: :default_pool,
    type: :atom,
    doc: """
    Reuse a browser from this pool instead of launching a new browser per test suite.
    """
  ],
  browser_pool_checkout_timeout: [
    default: to_timeout(minute: 1),
    type: :non_neg_integer
  ],
  browser_pools: [
    required: false,
    default: [[id: :default_pool]],
    type: {:list, {:non_empty_keyword_list, browser_pool_opts}},
    doc: """
    Supported keys:
    #{NimbleOptions.docs(browser_pool_opts, nest_level: 1)}
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
    type_doc: "`module | false`",
    doc: "`false` to disable, or a module that implements the `PlaywrightEx.JsLogger` behaviour."
  ],
  screenshot: [
    default: false,
    type: {:or, [:boolean, non_empty_keyword_list: screenshot_opts_schema]},
    type_doc: "`boolean/0 | Keyword.t/0`",
    doc: """
    Either a boolean or a keyword list:

    #{NimbleOptions.docs(screenshot_opts_schema, nest_level: 1)}
    """
  ],
  screenshot_dir: [
    default: "screenshots",
    type: :string
  ],
  selector_engines: [
    default: [],
    type: {:or, [:map, :keyword_list]},
    doc: """
    Define custom Playwright [selector engines](https://playwright.dev/docs/extensibility#custom-selector-engines).
    """
  ],
  slow_mo: browser_opts[:slow_mo],
  timeout: [
    default: to_timeout(second: 2),
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
  ws_endpoint: [
    type: :string,
    doc: """
    WebSocket endpoint URL for connecting to a remote Playwright server.
    If provided, uses WebSocket transport instead of spawning a local Node.js process.
    Example: "ws://localhost:3000/ws"

    This is useful for:
    - Alpine Linux containers (glibc issues with local Playwright driver)
    - Containerized CI environments with a separate Playwright server
    - Connecting to remote/shared Playwright instances
    """
  ]
]

schema = NimbleOptions.new!(schema_opts)

setup_all_keys = ~w(browser_pool browser browser_launch_timeout executable_path headless slow_mo)a
setup_keys = ~w(accept_dialogs ecto_sandbox_stop_owner_delay screenshot trace browser_context_opts browser_page_opts)a
merge_global_into_browser_pool_keys = ~w(browser browser_launch_timeout headless slow_mo)a

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
  @schema_opts schema_opts
  @screenshot_opts_schema screenshot_opts_schema
  @setup_all_keys setup_all_keys
  @merge_global_into_browser_pool_keys merge_global_into_browser_pool_keys
  @setup_keys setup_keys
  @playwright_recommended_version playwright_recommended_version

  @doc false
  def schema_opts, do: @schema_opts

  @doc false
  def executable do
    [global()[:assets_dir], "node_modules", "playwright", "cli.js"] |> Path.join() |> Path.expand()
  end

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

  @doc false
  def global(:browser_pools) do
    all = Application.get_env(:phoenix_test, :playwright, [])
    global = Keyword.take(all, @merge_global_into_browser_pool_keys)

    all
    |> update_in([:browser_pools], &if(&1, do: Enum.map(&1, fn p -> Keyword.merge(global, p) end)))
    |> NimbleOptions.validate!(@schema)
    |> normalize()
    |> Keyword.fetch!(:browser_pools)
  end

  def global(key), do: Keyword.fetch!(global(), key)

  @doc false
  def setup_all_keys, do: @setup_all_keys

  @doc false
  def setup_keys, do: @setup_keys

  defp normalize(config), do: Keyword.new(config, fn {key, value} -> {key, normalize(key, value)} end)

  defp normalize(:screenshot, true), do: NimbleOptions.validate!([], @screenshot_opts_schema)
  defp normalize(_key, value), do: value

  def __validate_assets_dir__(assets_dir) do
    all = Application.get_env(:phoenix_test, :playwright, [])

    error_msg = """
    Could not find Playwright in `#{assets_dir}`.

    To resolve this, either:
    1. Install Playwright locally: `npm --prefix #{assets_dir} install playwright`
    2. Or configure a remote Playwright server via `ws_endpoint` option
    """

    cond do
      all[:ws_endpoint] -> {:ok, assets_dir}
      not playwright_installed?(assets_dir) -> {:error, error_msg}
      true -> {:ok, assets_dir}
    end
  end

  defp playwright_installed?(assets_dir) do
    playwright_json = Path.join([assets_dir, "node_modules", "playwright", "package.json"])

    with {:ok, string} <- File.read(playwright_json),
         {:ok, json} <- Phoenix.json_library().decode(string) do
      version = json["version"] || "0"

      if Version.compare(version, @playwright_recommended_version) == :lt do
        IO.warn("Playwright version #{version} is below recommended #{@playwright_recommended_version}")
      end

      true
    else
      _ -> false
    end
  end
end
