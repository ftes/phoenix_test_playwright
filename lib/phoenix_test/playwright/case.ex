setup_all_config_keys = ~w(browser headless slow_mo)a
setup_config_keys = ~w(screenshot trace)a

defmodule PhoenixTest.Playwright.Case do
  @moduledoc """
  ExUnit case module to assist with browser based tests.
  `PhoenixTest.Playwright` and `PhoenixTest.Playwright.Config` explain
  how to use and configure this module.

  If the default setup behaviour and order does not suit you, consider
  - using config opt `browser_context_opts`, which are passed to `PlaywrightEx.Browser.new_context/2`
  - using config opt `browser_page_opts`, which are passed to `PlaywrightEx.BrowserContext.new_page/2`
  - implementing your own `Case` (the setup functions in this module are public for your convenience)
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox, as: EctoSandbox
  alias Phoenix.Ecto.SQL.Sandbox, as: PhoenixSandbox
  alias PhoenixTest.Playwright
  alias PhoenixTest.Playwright.BrowserPool
  alias PlaywrightEx.Browser
  alias PlaywrightEx.BrowserContext
  alias PlaywrightEx.Page
  alias PlaywrightEx.Tracing

  using opts do
    quote do
      import PhoenixTest

      import PhoenixTest.Playwright,
        # styler:sort
        only: [
          add_cookies: 2,
          add_session_cookie: 3,
          clear_cookies: 1,
          clear_cookies: 2,
          click: 2,
          click: 3,
          click: 4,
          click_button: 4,
          click_link: 4,
          drag: 3,
          press: 3,
          press: 4,
          screenshot: 2,
          screenshot: 3,
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
  Adds `:browser_id` to the context.
  """
  def do_setup_all(context) do
    keys = Playwright.Config.setup_all_keys()
    config = context |> Map.take(keys) |> Playwright.Config.validate!() |> Keyword.take(keys)

    if pool = config[:browser_pool] do
      [browser_id: BrowserPool.checkout(pool)]
    else
      [browser_id: config |> Keyword.delete(:browser_pool) |> launch_browser()]
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
    {timeout, opts} = Keyword.pop!(config, :browser_launch_timeout)
    {browser, opts} = Keyword.pop!(opts, :browser)

    {:ok, browser} = PlaywrightEx.launch_browser(browser, Keyword.put(opts, :timeout, timeout))
    on_exit(fn -> spawn(fn -> Browser.close(browser.guid, timeout: timeout) end) end)
    browser.guid
  end

  def new_session(config, context) do
    user_agent = checkout_ecto_repos(config, context) || "No user agent"
    base_url = Application.fetch_env!(:phoenix_test, :base_url)
    context_opts_defaults = [base_url: base_url, locale: "en", user_agent: user_agent, timeout: config[:timeout]]
    context_opts = Keyword.merge(context_opts_defaults, config[:browser_context_opts])
    {:ok, browser_context} = Browser.new_context(context.browser_id, context_opts)
    register_selector_engines!(browser_context.guid, config)

    page_opts = Keyword.merge([timeout: config[:timeout]], config[:browser_page_opts])
    {:ok, page} = BrowserContext.new_page(browser_context.guid, page_opts)
    {:ok, _} = Page.update_subscription(page.guid, event: :console, enabled: true, timeout: config[:timeout])
    {:ok, _} = Page.update_subscription(page.guid, event: :dialog, enabled: true, timeout: config[:timeout])
    on_exit(fn -> spawn(fn -> BrowserContext.close(browser_context.guid, timeout: config[:timeout]) end) end)

    if config[:trace], do: trace(browser_context.tracing.guid, config, context)
    if config[:screenshot], do: screenshot(page.guid, config, context)

    Playwright.build(%{
      context_id: browser_context.guid,
      page_id: page.guid,
      frame_id: page.main_frame.guid,
      tracing_id: browser_context.tracing.guid,
      config: config
    })
  end

  defp register_selector_engines!(browser_context_id, config) do
    for {name, source} <- PhoenixTest.Playwright.Selector.Engines.custom() do
      {:ok, _} =
        BrowserContext.register_selector_engine(browser_context_id,
          selector_engine: [name: to_string(name), source: source],
          timeout: config[:timeout]
        )
    end
  end

  defp trace(tracing_id, config, context) do
    opts = [screenshots: true, snapshots: true, sources: true, timeout: config[:timeout]]
    {:ok, _} = Tracing.tracing_start(tracing_id, opts)
    {:ok, _} = Tracing.tracing_start_chunk(tracing_id, timeout: config[:timeout])

    File.mkdir_p!(config[:trace_dir])
    file = Path.join(config[:trace_dir], file_name("_#{System.unique_integer([:positive, :monotonic])}.zip", context))

    on_exit(fn ->
      {:ok, zip_file} = Tracing.tracing_stop_chunk(tracing_id, timeout: config[:timeout])
      {:ok, _} = Tracing.tracing_stop(tracing_id, timeout: config[:timeout])

      File.cp!(zip_file.absolute_path, file)
      maybe_open_trace(config[:trace], file)
    end)
  end

  defp maybe_open_trace(:open, path) do
    # Spawn to avoid blocking the test exit
    spawn(fn -> System.cmd(Playwright.Config.executable(), ["show-trace", Path.absname(path)]) end)
    :ok
  end

  defp maybe_open_trace(_, _), do: :ok

  defp screenshot(page_id, config, context) do
    file = file_name(".png", context)

    on_exit(fn ->
      Playwright.screenshot(%{page_id: page_id}, file, config[:screenshot])
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
      case start_sandbox_owner(repo, context) do
        {:ok, pid} ->
          on_exit(fn -> stop_sandbox_owner(pid, config, context) end)

        _ ->
          :ok
      end

      repo
    end

    defp start_sandbox_owner(repo, context) do
      pid = EctoSandbox.start_owner!(repo, shared: not context.async)
      {:ok, pid}
    rescue
      _ -> {:error, :probably_already_started}
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
      nil
    end
  end
end
