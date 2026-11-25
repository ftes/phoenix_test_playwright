# styler:sort
schema_opts = [
  accept_dialogs: [
    default: true,
    type: :boolean,
    doc: "Accept browser dialogs (`alert()`, `confirm()`, `prompt()`)."
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
  ]
]

schema = NimbleOptions.new!(schema_opts)

setup_keys = ~w(accept_dialogs ecto_sandbox_stop_owner_delay)a

defmodule PhoenixTest.Playwright.Config do
  @moduledoc """
  Configuration options for the Playwright driver.

  Most should be set globally in `config/test.exs`.
  Some can be overridden per test.

  All options:
  #{NimbleOptions.docs(schema)}

  Options that can be overridden per test module (`use PhoenixTest.Playwright.Case` opts) or
  per test (`@tag`, `@describetag`):
  #{Enum.map_join(setup_keys, "\n", &"- `:#{&1}`")}

  Every other option of `use PhoenixTest.Playwright.Case` but ExUnit's goes to `use Playwright.Test`,
  which raises for an unknown one: Playwright's options, e.g. `browser_name: :firefox`,
  `launch_options: [headless: false, slow_mo: 500]`, `locale: "de-DE"` or `trace: :on`.

  ## Playwright options

  Browsers come from `Playwright.Test.BrowserPool`, and each test is registered with
  `Playwright.Test`. So `config :playwright, :test` applies too, e.g. for
  traces, screenshots and videos (also as `@tag Playwright.Test.use(trace: :on)`), `workers` and `output_dir`:

      config :playwright, :test,
        browser_name: :chromium,
        launch_options: [headless: false, slow_mo: 500],
        context_options: [locale: "de-DE"],
        trace: :retain_on_failure,
        screenshot: :only_on_failure

  It also resolves `assert_screenshot/3` baselines (`snapshot_dir`, `snapshot_path_template`).
  A module sets them in its `use` options; a describe block or a test with `@tag Playwright.Test.use(locale: "fr-FR")`
  (context options and recording only); a run of the module with `parameterize:` and `Playwright.Test.parameters/1`,
  e.g. `Playwright.Test.parameters(name: "firefox", browser_name: :firefox)`. See `Playwright.Test`.

  ## Timeouts

  Playwright's timeouts apply, as Playwright Test's. Actions wait up to
  `config :playwright, :test, action_timeout: ...`, navigations (`visit/3`, `reload_page/2`)
  up to `navigation_timeout`. Both are unlimited by default: the test's ExUnit timeout bounds them.
  Assertions (`assert_has`, `refute_has`, `assert_path`, `assert_download`, `assert_screenshot/3`)
  retry up to `config :playwright, :test, expect: [timeout: ...]`, 5 seconds by default.

      config :playwright, :test, action_timeout: 2_000, navigation_timeout: 5_000, expect: [timeout: 2_000]

  An operation's `timeout:` option overrides them, in milliseconds or `:infinity` for no limit.
  As in phoenix_test, an assertion's `timeout: 0` checks once; actions and `assert_screenshot/3`
  reject `0`. In `config :playwright`, `0` is Playwright's no timeout.
  See `Playwright.Test` and `Playwright.Expect`.
  """

  @schema schema
  @setup_keys setup_keys

  # Options of earlier versions, now Playwright's. `browser` only with a browser's name: a
  # `@moduletag :browser` filter tag is the user's.
  @removed_options [
    browser:
      "`browser_name` (`use PhoenixTest.Playwright.Case, browser_name: :firefox` or " <>
        "`Playwright.Test.parameters(name: \"firefox\", browser_name: :firefox)`)",
    browser_launch_opts: "`launch_options` (`use PhoenixTest.Playwright.Case, launch_options: [slow_mo: 500]`)",
    browser_context_opts:
      "Playwright's context options (`use PhoenixTest.Playwright.Case, locale: \"de-DE\"` or " <>
        "`@tag Playwright.Test.use(locale: \"de-DE\")`), or for values a setup computes " <>
        "`PhoenixTest.Playwright.Case.do_setup(context, storage_state: ...)`"
  ]

  @doc false
  # Raises for a removed option in `options` (a keyword list, or a test's context), which would
  # be ignored or rejected without a hint. Returns `options`.
  def reject_removed!(options, where) do
    given = Map.new(options)

    for {key, instead} <- @removed_options,
        Map.has_key?(given, key),
        key != :browser or given.browser in [:chromium, :firefox, :webkit] do
      raise ArgumentError, "#{where}: the `#{key}` option of PhoenixTest.Playwright was removed, use #{instead}"
    end

    options
  end

  @doc false
  # A map is a test's context: only its per-test options (`setup_keys/0`) apply.
  def validate!(context) when is_map(context), do: context |> Map.take(@setup_keys) |> Keyword.new() |> validate!()

  def validate!(config) when is_list(config) do
    global = Application.get_env(:phoenix_test, :playwright, [])
    reject_removed!(global, "config :phoenix_test, :playwright")

    global
    |> Keyword.merge(config)
    |> NimbleOptions.validate!(@schema)
  end

  @doc false
  def global, do: validate!([])

  def global(key), do: Keyword.fetch!(global(), key)

  @doc false
  def setup_keys, do: @setup_keys
end
