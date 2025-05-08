setup_all_config_keys = ~w(browser headless slow_mo)a
setup_config_keys = ~w(screenshot trace)a

defmodule PhoenixTest.Playwright.Case do
  @moduledoc """
  ExUnit case module to assist with browser based tests.

  See `PhoenixTest.Playwright` and `PhoenixTest.Playwright.Config`
  for more information.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox
  alias PhoenixTest.Playwright
  alias PhoenixTest.Playwright.Case
  alias PhoenixTest.Playwright.Config

  using opts do
    quote do
      import PhoenixTest

      import PhoenixTest.Playwright,
        only: [
          add_cookies: 2,
          add_session_cookie: 3,
          clear_cookies: 1,
          clear_cookies: 2,
          click: 3,
          click: 4,
          click_button: 4,
          click_link: 4,
          press: 3,
          press: 4,
          screenshot: 2,
          screenshot: 3,
          type: 3,
          type: 4,
          with_dialog: 3
        ]

      import PhoenixTest.Playwright.Case

      @moduletag Keyword.delete(unquote(opts), :async)
    end
  end

  setup_all context do
    keys = Config.setup_all_keys()
    config = context |> Map.take(keys) |> Config.validate!() |> Keyword.take(keys)
    [browser_id: Case.Playwright.launch_browser(config)]
  end

  setup context do
    config = context |> Map.take(Config.setup_keys()) |> Config.validate!()
    [conn: Case.Playwright.new_session(config, context)]
  end

  defmodule Playwright do
    @moduledoc false
    import PhoenixTest.Playwright.Connection

    alias PhoenixTest.Playwright.Browser
    alias PhoenixTest.Playwright.BrowserContext
    alias PhoenixTest.Playwright.Page
    alias PhoenixTest.Playwright.Port

    @includes_ecto Code.ensure_loaded?(Sandbox) &&
                     Code.ensure_loaded?(Phoenix.Ecto.SQL.Sandbox)

    def launch_browser(opts) do
      ensure_started()
      {browser, opts} = Keyword.pop!(opts, :browser)
      browser_id = launch_browser(browser, opts)
      on_exit(fn -> post(guid: browser_id, method: :close) end)
      browser_id
    end

    def new_session(config, context) do
      browser_context_opts = %{
        locale: "en",
        user_agent: checkout_ecto_repos(context.async) || "No user agent"
      }

      browser_context_id = Browser.new_context(context.browser_id, browser_context_opts)

      page_id = BrowserContext.new_page(browser_context_id)
      Page.update_subscription(page_id, event: :console, enabled: true)
      Page.update_subscription(page_id, event: :dialog, enabled: true)

      frame_id = initializer(page_id).main_frame.guid
      on_exit(fn -> post(guid: browser_context_id, method: :close) end)

      if config[:trace], do: trace(browser_context_id, config, context)
      if config[:screenshot], do: screenshot(page_id, config, context)

      PhoenixTest.Playwright.build(%{
        context_id: browser_context_id,
        page_id: page_id,
        frame_id: frame_id,
        config: config
      })
    end

    defp trace(browser_context_id, config, context) do
      BrowserContext.start_tracing(browser_context_id)

      File.mkdir_p!(config[:trace_dir])
      file = file_name("_#{System.unique_integer([:positive, :monotonic])}.zip", context)
      path = Path.join(config[:trace_dir], file)

      on_exit(fn ->
        BrowserContext.stop_tracing(browser_context_id, path)

        if config[:trace] == :open do
          cli_path = Path.join(File.cwd!(), Port.cli_path())
          System.cmd(cli_path, ["show-trace", path])
        end
      end)
    end

    defp screenshot(page_id, config, context) do
      file = file_name(".png", context)
      on_exit(fn -> PhoenixTest.Playwright.screenshot(%{page_id: page_id}, file, config[:screenshot]) end)
    end

    defp file_name(suffix, %{module: module, test: test}) do
      "Elixir." <> module = to_string(module)
      time = :second |> :erlang.system_time() |> to_string()
      String.replace("#{module}.#{test}_#{time}#{suffix}", ~r/[^a-zA-Z0-9\.]/, "_")
    end

    if @includes_ecto do
      def checkout_ecto_repos(async?) do
        otp_app = Application.fetch_env!(:phoenix_test, :otp_app)
        repos = Application.get_env(otp_app, :ecto_repos, [])

        repos
        |> Enum.map(&checkout_ecto_repo(&1, async?))
        |> Phoenix.Ecto.SQL.Sandbox.metadata_for(self())
        |> Phoenix.Ecto.SQL.Sandbox.encode_metadata()
      end

      defp checkout_ecto_repo(repo, async?) do
        case Sandbox.checkout(repo) do
          :ok -> :ok
          {:already, :allowed} -> :ok
          {:already, :owner} -> :ok
        end

        if not async?, do: Sandbox.mode(repo, {:shared, self()})

        repo
      end
    else
      def checkout_ecto_repos(_) do
        nil
      end
    end
  end
end
