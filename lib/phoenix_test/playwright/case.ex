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

  Options other than `:async` become module tags, so they can override config per module,
  e.g. `browser_pool: :exclusive`. `:parameterize` is the `ExUnit.Case` option:
  it runs the module once per map, and the maps can set config too.

  Browsers come from `PlaywrightEx.Test.BrowserPool`, and each test is registered with
  `PlaywrightEx.Test`: traces, screenshots and videos are recorded as
  `config :playwright_ex, :test` and the `trace`, `screenshot` and `video` tags say,
  into `test-results/` (see `PhoenixTest.Playwright.Config`).

  If the default setup behaviour and order does not suit you, consider
  - using config opt `browser_context_opts`, which are passed to `PlaywrightEx.Browser.new_context/2`
  - implementing your own `Case` (the setup functions in this module are public for your convenience).
    `use PlaywrightEx.Test` must be the first line of its body, so tests are registered
    before `do_setup/1` creates their browser context.

  Browser contexts are closed before their ExUnit teardown callbacks return.
  """

  use ExUnit.CaseTemplate
  use PlaywrightEx.Test

  alias Ecto.Adapters.SQL.Sandbox, as: EctoSandbox
  alias Phoenix.Ecto.SQL.Sandbox, as: PhoenixSandbox
  alias PhoenixTest.Playwright
  alias PhoenixTest.Playwright.JsLogger
  alias PlaywrightEx.Browser
  alias PlaywrightEx.BrowserContext

  using opts do
    quote do
      use PlaywrightEx.Test

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

      @moduletag Keyword.delete(unquote(opts), :async)
    end
  end

  setup_all :do_setup_all
  setup :do_setup

  @doc """
  Merges the ExUnit context with `PhoenixTest.Playwright.Config` opts.
  Uses the result to get a browser from `PlaywrightEx.Test.BrowserPool`
  (an exclusive one is held by the test module).
  Adds `:playwright_browser` to the context.
  """
  def do_setup_all(context) do
    keys = Playwright.Config.setup_all_keys()
    config = context |> Map.take(keys) |> Playwright.Config.validate!() |> Keyword.take(keys)
    [playwright_browser: Playwright.Browser.browser!(config)]
  end

  @doc """
  Merges the ExUnit context with `PhoenixTest.Playwright.Config` opts.
  Uses the result to create a new browser context and page.
  Adds `:conn` to the context.
  """
  def do_setup(context) do
    config = context |> Map.take(Playwright.Config.setup_keys()) |> Playwright.Config.validate!()
    [conn: new_session(config, context)]
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
    base_url = Application.fetch_env!(:phoenix_test, :base_url)
    context_opts_defaults = [base_url: base_url, user_agent: user_agent]
    context_opts = Keyword.merge(context_opts_defaults, config[:browser_context_opts])
    browser_context = Browser.new_context!(context.playwright_browser, context_opts)
    JsLogger.attach(browser_context, Playwright.Config.global(:js_logger))

    page = BrowserContext.new_page!(browser_context)

    # Before the sandbox owner stops (registered earlier, so it runs later).
    on_exit(fn -> BrowserContext.close(browser_context) end)

    Playwright.build(%{context: browser_context, page: page, config: config})
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
