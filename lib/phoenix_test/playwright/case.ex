defmodule PhoenixTest.Playwright.Case do
  @moduledoc """
  ExUnit case module to assist with browser based tests.
  See the [README](README.md#getting-started) to get started and
  `PhoenixTest.Playwright.Config` for all options.

      defmodule MyAppWeb.RegisterTest do
        use PhoenixTest.Playwright.Case,
          async: true,
          parameterize: [%{browser: :chromium}, %{browser: :firefox}]

        test "register", %{conn: conn} do
          conn
          |> visit("/register")
          |> assert_has("h1", text: "Register")
        end
      end

  `:trace`, `:screenshot` and `:video` go to `use Playwright.Test`, e.g. `trace: :on`.
  Other options than `:async` become module tags, so they can override config per module,
  e.g. `browser: :firefox`. `:parameterize` is the `ExUnit.Case` option:
  it runs the module once per map, and the maps can set config too. Recording modes in a map go
  through `Playwright.Test.parameters/1`, as plain keys are ignored:
  `Map.put(Playwright.Test.parameters(trace: :on), :browser, :firefox)`.

  Browsers come from `Playwright.Test.BrowserPool`, and each test is registered with
  `Playwright.Test`: traces, screenshots and videos are recorded as
  `config :playwright, :test` and `Playwright.Test.use/1` tags say (`@tag Playwright.Test.use(trace: :on)`),
  into `test-results/` (see `PhoenixTest.Playwright.Config`). Its resolved `base_url` wins over
  phoenix_test's, for pages and for cookies without a `url` or `domain`.

  If the default setup behaviour and order does not suit you, consider
  - using config opt `browser_context_opts`, which are passed to `Playwright.Browser.new_context/2`
  - implementing your own `Case` (the setup functions in this module are public for your convenience).
    `use Playwright.Test` must be the first line of its body, so tests are registered
    before `do_setup/1` creates their browser context.

  Browser contexts are closed before their ExUnit teardown callbacks return.
  """

  use ExUnit.CaseTemplate
  use Playwright.Test

  alias Ecto.Adapters.SQL.Sandbox, as: EctoSandbox
  alias Phoenix.Ecto.SQL.Sandbox, as: PhoenixSandbox
  # No `alias PhoenixTest.Playwright`: `Playwright.*` here is the playwright_ex dependency.
  alias PhoenixTest.Playwright.Config
  alias PhoenixTest.Playwright.JsLogger
  alias Playwright.Browser
  alias Playwright.BrowserContext

  # Options of `use PhoenixTest.Playwright.Case` passed to `use Playwright.Test`.
  @playwright_keys [:trace, :screenshot, :video]

  using opts do
    quote do
      use Playwright.Test, Keyword.take(unquote(opts), unquote(@playwright_keys))

      import PhoenixTest

      import PhoenixTest.Playwright,
        # styler:sort
        only: [
          add_cookies: 2,
          add_session_cookie: 3,
          assert_screenshot: 2,
          assert_screenshot: 3,
          clear_cookies: 1,
          click: 2,
          click: 3,
          click: 4,
          click_button: 4,
          click_link: 4,
          drag: 3,
          evaluate: 2,
          evaluate: 3,
          evaluate: 4,
          press: 3,
          press: 4,
          screenshot: 2,
          screenshot: 3,
          step: 3,
          type: 3,
          type: 4,
          visit: 3,
          with_dialog: 3
        ]

      @moduletag Keyword.drop(unquote(opts), [:async | unquote(@playwright_keys)])
    end
  end

  setup_all :do_setup_all
  setup :do_setup

  @doc """
  Merges the ExUnit context with `PhoenixTest.Playwright.Config` opts.
  Uses the result to get a browser from `Playwright.Test.BrowserPool`
  (held by the test module until it ends).
  Adds `:playwright_browser` to the context.
  """
  def do_setup_all(context) do
    keys = Config.setup_all_keys()
    config = context |> Map.take(keys) |> Config.validate!() |> Keyword.take(keys)
    [playwright_browser: PhoenixTest.Playwright.Browser.browser!(config)]
  end

  @doc """
  Merges the ExUnit context with `PhoenixTest.Playwright.Config` opts.
  Uses the result to create a new browser context and page.
  Adds `:conn` to the context.
  """
  def do_setup(context) do
    warn_plain_recording_tags(context)
    config = context |> Map.take(Config.setup_keys()) |> Config.validate!()
    [conn: new_session(config, context)]
  end

  # Playwright.Test ignores plain `trace`, `screenshot` and `video` tags, which ptp documented before.
  defp warn_plain_recording_tags(context) do
    for key <- @playwright_keys,
        Map.has_key?(context, key),
        warned = {__MODULE__, :warned, context.module, key},
        not :persistent_term.get(warned, false) do
      :persistent_term.put(warned, true)

      IO.warn(
        "#{inspect(context.module)}: the plain `#{key}` tag (or parameterize: key) records nothing, " <>
          "use `@tag Playwright.Test.use(#{key}: ...)` or `Playwright.Test.parameters(#{key}: ...)`",
        []
      )
    end
  end

  @doc """
  Creates a fresh browser context and page, and returns a `conn` for them.

  `config` is a validated config, `context` is the ExUnit test context (with `:playwright_browser`).
  The browser context is closed when the test exits.

  For another session within the same test, e.g. a second user, `do_setup/1` calls this
  with the test's own config:

      test "two users chat", context do
        [conn: other_conn] = PhoenixTest.Playwright.Case.do_setup(context)
        # ...
      end
  """
  def new_session(config, context) do
    user_agent = checkout_ecto_repos(config, context)
    # A call's options win over Playwright's resolved ones, so phoenix_test's `base_url` goes in only without one.
    playwright_base_url = playwright_base_url()
    phoenix_base_url = if playwright_base_url, do: [], else: [base_url: Application.fetch_env!(:phoenix_test, :base_url)]

    context_opts = Keyword.merge([user_agent: user_agent] ++ phoenix_base_url, config[:browser_context_opts])
    browser_context = Browser.new_context!(context.playwright_browser, context_opts)
    JsLogger.attach(browser_context, Config.global(:js_logger))

    page = BrowserContext.new_page!(browser_context)

    # Before the sandbox owner stops (registered earlier, so it runs later).
    on_exit(fn -> BrowserContext.close(browser_context) end)

    base_url = context_opts[:base_url] || playwright_base_url
    PhoenixTest.Playwright.build(%{context: browser_context, page: page, config: config, base_url: base_url})
  end

  # The test's resolved `base_url`; outside a test (e.g. `setup_all`) the config's.
  defp playwright_base_url do
    if Playwright.Test.in_registered_test?() do
      Playwright.Test.info().use[:base_url]
    else
      config = Playwright.Test.config()
      config.base_url || config.context_options[:base_url]
    end
  end

  @includes_ecto Code.ensure_loaded?(EctoSandbox) && Code.ensure_loaded?(PhoenixSandbox)

  if @includes_ecto do
    defp checkout_ecto_repos(config, context) do
      otp_app = Application.fetch_env!(:phoenix_test, :otp_app)
      repos = Application.get_env(otp_app, :ecto_repos, [])

      repos
      |> Enum.map(&maybe_start_sandbox_owner(&1, config, context))
      |> PhoenixSandbox.metadata_for(self())
      |> PhoenixSandbox.encode_metadata()
    end

    defp maybe_start_sandbox_owner(repo, config, context) do
      pid = EctoSandbox.start_owner!(repo, shared: not context.async)
      on_exit(fn -> stop_sandbox_owner(pid, config, context) end)
      repo
    rescue
      e in MatchError ->
        case e do
          %MatchError{term: {:error, {{:badmatch, {:already, :allowed}}, _}}} ->
            # Already checked out (e.g. second new_session call in same test)
            repo

          %MatchError{term: {:error, {{:badmatch, :already_shared}, _}}} ->
            # Already shared (e.g. second new_session call in same async: false test)
            repo

          _ ->
            reraise e, __STACKTRACE__
        end
    end

    defp stop_sandbox_owner(checkout_pid, config, context) do
      if context.async do
        spawn(fn -> do_stop_sandbox_owner(checkout_pid, config) end)
      else
        do_stop_sandbox_owner(checkout_pid, config)
      end
    end

    defp do_stop_sandbox_owner(checkout_pid, config) do
      delay = Keyword.fetch!(config, :ecto_sandbox_stop_owner_delay)
      if delay > 0, do: Process.sleep(delay)
      EctoSandbox.stop_owner(checkout_pid)
    end
  else
    defp checkout_ecto_repos(_, _) do
      "Ecto not loaded"
    end
  end
end
