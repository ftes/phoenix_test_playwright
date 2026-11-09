defmodule PhoenixTest.Playwright.Case do
  @moduledoc """
  ExUnit case module to assist with browser based tests.
  See the [README](README.md#getting-started) to get started and
  `PhoenixTest.Playwright.Config` for all options.

      defmodule MyAppWeb.RegisterTest do
        use PhoenixTest.Playwright.Case,
          async: true,
          parameterize: [%{browser_pool: :chromium_pool}, %{browser_pool: :firefox_pool}]

        test "register", %{conn: conn} do
          conn
          |> visit("/register")
          |> assert_has("h1", text: "Register")
        end
      end

  Options other than `:async` become module tags, so they can override config per module,
  e.g. `browser_pool: false`. `:parameterize` is the `ExUnit.Case` option:
  it runs the module once per map, and the maps can set config too.

  If the default setup behaviour and order does not suit you, consider
  - using config opt `browser_context_opts`, which are passed to `PlaywrightEx.Browser.new_context/2`
  - implementing your own `Case` (the setup functions in this module are public for your convenience)

  Browser contexts and non-pooled browsers are closed before their ExUnit
  teardown callbacks return.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox, as: EctoSandbox
  alias Phoenix.Ecto.SQL.Sandbox, as: PhoenixSandbox
  alias PhoenixTest.Playwright
  alias PhoenixTest.Playwright.BrowserPool
  alias PhoenixTest.Playwright.JsLogger
  alias PlaywrightEx.Browser
  alias PlaywrightEx.BrowserContext
  alias PlaywrightEx.Tracing

  using opts do
    quote do
      import PhoenixTest

      import PhoenixTest.Playwright,
        # styler:sort
        only: [
          add_cookies: 2,
          add_session_cookie: 3,
          assert_screenshot: 2,
          assert_screenshot: 3,
          clear_cookies: 1,
          clear_cookies: 2,
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
      def timeout, do: PhoenixTest.Playwright.Config.global(:timeout)
    end
  end

  setup_all :do_setup_all
  setup :do_setup

  @doc """
  Merges the ExUnit context with `PhoenixTest.Playwright.Config` opts.
  Uses the result to launch the browser.
  Adds `:playwright_browser` to the context.
  """
  def do_setup_all(context) do
    keys = Playwright.Config.setup_all_keys()
    config = context |> Map.take(keys) |> Playwright.Config.validate!() |> Keyword.take(keys)

    if pool = config[:browser_pool] do
      [playwright_browser: BrowserPool.checkout(pool)]
    else
      [playwright_browser: launch_browser(config)]
    end
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

  defp launch_browser(config) do
    timeout = Keyword.fetch!(config, :browser_launch_timeout)
    browser = PhoenixTest.Playwright.Browser.launch_browser!(config)

    on_exit(fn -> Playwright.Browser.within(timeout, fn -> Browser.close(browser) end) end)

    browser
  end

  @doc """
  Creates a fresh browser context and page, and returns a `conn` for them.
  Use it for another session within the same test, e.g. a second user.

  `config` is a validated config, `context` is the ExUnit test context (with `:playwright_browser`).
  The browser context is closed when the test exits.

      test "two users chat", context do
        config = PhoenixTest.Playwright.Config.validate!(%{})
        other_conn = PhoenixTest.Playwright.Case.new_session(config, context)
        # ...
      end
  """
  def new_session(config, context) do
    user_agent = checkout_ecto_repos(config, context)
    base_url = Application.fetch_env!(:phoenix_test, :base_url)
    context_opts_defaults = [base_url: base_url, locale: "en", user_agent: user_agent]
    context_opts = context_opts_defaults |> Keyword.merge(config[:browser_context_opts]) |> normalize_context_opts()
    browser_context = Browser.new_context!(context.playwright_browser, context_opts)
    JsLogger.attach(browser_context, Playwright.Config.global(:js_logger))

    page = BrowserContext.new_page!(browser_context)

    on_exit(fn ->
      Playwright.Browser.within(config[:timeout], fn -> BrowserContext.close(browser_context) end)
    end)

    tracing = BrowserContext.tracing(browser_context)
    if config[:trace], do: start_trace(tracing, config, context)

    %{context: browser_context, page: page, config: config}
    |> Playwright.build()
    |> tap(fn conn ->
      if config[:screenshot], do: screenshot(conn, config, context)
    end)
  end

  # Forms that PlaywrightEx 0.15 accepted and 0.17 would silently ignore.
  defp normalize_context_opts(opts) do
    Enum.map(opts, fn
      {:viewport, nil} -> {:viewport, :null}
      {:extra_http_headers, headers} -> {:extra_http_headers, Map.new(headers, &normalize_header/1)}
      opt -> opt
    end)
  end

  defp normalize_header(%{name: name, value: value}), do: {to_string(name), to_string(value)}
  defp normalize_header({name, value}), do: {to_string(name), to_string(value)}

  defp start_trace(tracing, config, context) do
    Tracing.start!(tracing, screenshots: true, snapshots: true)

    File.mkdir_p!(config[:trace_dir])
    file = Path.join(config[:trace_dir], file_name("_#{System.unique_integer([:positive, :monotonic])}.zip", context))

    on_exit(fn ->
      Tracing.stop!(tracing, path: file)

      maybe_open_trace(config[:trace], file)
    end)
  end

  defp maybe_open_trace(:open, path) do
    # Spawn to avoid blocking the test exit
    spawn(fn ->
      {program, args} = PlaywrightEx.Driver.executable()
      System.cmd(program, args ++ ["show-trace", Path.absname(path)])
    end)

    :ok
  end

  defp maybe_open_trace(_, _), do: :ok

  # Dialyzer warning suppressed: conn is opaque t() but closure captures struct
  @dialyzer {:nowarn_function, screenshot: 3}
  defp screenshot(conn, config, context) do
    file = file_name(".png", context)

    on_exit(fn ->
      Playwright.screenshot(conn, file, config[:screenshot])
    end)
  end

  defp file_name(suffix, %{module: module, test: test}) do
    "Elixir." <> module = to_string(module)
    time = :second |> :erlang.system_time() |> to_string()
    String.replace("#{module}.#{test}_#{time}#{suffix}", ~r/[^a-zA-Z0-9\.]/, "_")
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
