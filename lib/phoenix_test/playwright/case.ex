defmodule PhoenixTest.Playwright.Case do
  @moduledoc """
  ExUnit case module to assist with browser based tests.
  See the [README](README.md#getting-started) to get started and
  `PhoenixTest.Playwright.Config` for all options.

      defmodule MyAppWeb.RegisterTest do
        use PhoenixTest.Playwright.Case,
          async: true,
          parameterize: [
            Playwright.Test.parameters(name: "chromium", browser_name: :chromium),
            Playwright.Test.parameters(name: "firefox", browser_name: :firefox)
          ]

        test "register", %{conn: conn} do
          conn
          |> visit("/register")
          |> assert_has("h1", text: "Register")
        end
      end

  The options of `PhoenixTest.Playwright.Config` (`accept_dialogs`, `ecto_sandbox_stop_owner_delay`)
  become module tags. Every other option but ExUnit's goes to `use Playwright.Test`, e.g.
  `browser_name: :firefox`, `launch_options: [slow_mo: 500]`, `locale: "de-DE"` or `trace: :on`,
  and an unknown one raises. `:parameterize` is the `ExUnit.Case` option: it runs the module once
  per `Playwright.Test.parameters/1` project, and a `name:` labels its failures and its snapshots.

  Browsers come from `Playwright.Test.BrowserPool`, and each test is registered with
  `Playwright.Test`: its options (`config :playwright, :test`, the project's, the module's and
  `@tag Playwright.Test.use(...)`) set the browser, the context and the recording of traces,
  screenshots and videos into `test-results/` (see `PhoenixTest.Playwright.Config`). Its resolved
  `base_url` wins over phoenix_test's, for pages and for cookies without a `url` or `domain`, and
  the Ecto sandbox's metadata is appended to its `user_agent`.

  If the default setup behaviour and order does not suit you, consider
  implementing your own `Case` (the setup functions in this module are public for your convenience).
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

  # Options of `use PhoenixTest.Playwright.Case` kept as module tags; the others but ExUnit's go to
  # `use Playwright.Test`, which ignores ExUnit's and raises for unknown ones.
  @config_keys Config.setup_keys()
  # Recording modes, which Playwright.Test reads from `Playwright.Test.use/1` tags only.
  @recording_keys [:trace, :screenshot, :video]
  using opts do
    # Split as the template expands: `use Playwright.Test` validates its options as it expands, and
    # reads some (`assert_steps`) only from a literal keyword list. Removed options are rejected
    # first, as `use Playwright.Test` would reject them without a hint.
    {use_opts, config_opts} =
      if Keyword.keyword?(opts) do
        Config.reject_removed!(opts, "use PhoenixTest.Playwright.Case in #{inspect(__CALLER__.module)}")
        {Keyword.drop(opts, @config_keys), Keyword.take(opts, @config_keys)}
      else
        {quote(do: Keyword.drop(unquote(opts), unquote(@config_keys))),
         quote(do: Keyword.take(unquote(opts), unquote(@config_keys)))}
      end

    quote do
      use Playwright.Test, unquote(use_opts)

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

      @moduletag unquote(config_opts)
    end
  end

  setup_all :do_setup_all
  setup :do_setup

  @doc """
  Gets a browser from `Playwright.Test.BrowserPool` (held by the test module until it ends),
  of the module's `browser_name` and `launch_options`.
  Adds `:playwright_browser` to the context.
  """
  def do_setup_all(context) do
    Config.reject_removed!(context, inspect(Map.get(context, :module)))
    [playwright_browser: PhoenixTest.Playwright.Browser.browser!()]
  end

  @doc """
  Merges the ExUnit context with `PhoenixTest.Playwright.Config` opts.
  Uses the result to create a new browser context and page.
  Adds `:conn` to the context.
  """
  def do_setup(context) do
    Config.reject_removed!(context, inspect(Map.get(context, :module)))
    warn_plain_recording_tags(context)
    config = context |> Map.take(Config.setup_keys()) |> Config.validate!()
    [conn: new_session(config, context)]
  end

  @doc false
  # Playwright.Test ignores plain `trace`, `screenshot` and `video` tags, which ptp documented before.
  def warn_plain_recording_tags(context) do
    for key <- @recording_keys,
        Map.has_key?(context, key),
        module = Map.get(context, :module),
        warned = {__MODULE__, :warned, module, key},
        not :persistent_term.get(warned, false) do
      :persistent_term.put(warned, true)

      IO.warn(
        "#{inspect(module)}: the plain `#{key}` tag (or parameterize: key) records nothing, " <>
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

  `context_options` (`Playwright.Browser.new_context/2`'s) win over Playwright's resolved ones,
  for values only a setup computes, e.g. a logged-in `storage_state`:

      setup context do
        config = context |> Map.take(PhoenixTest.Playwright.Config.setup_keys()) |> PhoenixTest.Playwright.Config.validate!()
        [conn: PhoenixTest.Playwright.Case.new_session(config, context, storage_state: log_in())]
      end
  """
  def new_session(config, context, context_options \\ []) do
    context_options = Keyword.new(context_options)
    use = Map.merge(Map.new(playwright_use()), Map.new(context_options))
    user_agent = user_agent(context_option(use, :user_agent), checkout_ecto_repos(config, context))
    # Passed explicitly, so the context and `conn.base_url` (for cookies) agree, in any process.
    base_url = context_option(use, :base_url) || Application.fetch_env!(:phoenix_test, :base_url)

    context_opts =
      context_options
      |> Keyword.merge(base_url: base_url, user_agent: user_agent)
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    browser_context = Browser.new_context!(context.playwright_browser, context_opts)
    JsLogger.attach(browser_context, Config.global(:js_logger))

    page = BrowserContext.new_page!(browser_context)

    # Before the sandbox owner stops (registered earlier, so it runs later).
    on_exit(fn -> BrowserContext.close(browser_context) end)

    PhoenixTest.Playwright.build(%{
      context: browser_context,
      page: page,
      config: config,
      base_url: base_url
    })
  end

  # The resolved options of the test or `setup_all`, else (another process) the config's.
  defp playwright_use do
    if Playwright.Test.in_registered_scope?(), do: Playwright.Test.info().use, else: Playwright.Test.config()
  end

  # The config (outside a scope) keeps a context option set only in its `context_options` bag there.
  defp context_option(use, key), do: use[key] || use[:context_options][key]

  # The resolved user agent (a device's, the config's) followed by the Ecto sandbox's metadata,
  # which `Phoenix.Ecto.SQL.Sandbox` reads from the user agent's last `/`-separated part.
  defp user_agent(user_agent, metadata) do
    case Enum.reject([user_agent, metadata], &is_nil/1) do
      [] -> nil
      parts -> Enum.join(parts, "/")
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
    defp checkout_ecto_repos(_, _), do: nil
  end
end
