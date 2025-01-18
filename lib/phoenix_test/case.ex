defmodule PhoenixTest.Case do
  @moduledoc """
  ExUnit case module to assist with browser based tests.
  See `PhoenixTest.Playwright` for more information.
  """

  use ExUnit.CaseTemplate

  alias PhoenixTest.Case
  alias PhoenixTest.Playwright

  using opts do
    quote do
      import PhoenixTest
      import PhoenixTest.Case
      import PhoenixTest.Playwright, only: [screenshot: 2, screenshot: 3]

      setup do
        [phoenix_test: unquote(opts)]
      end
    end
  end

  @playwright_opts [
    browser: :chromium,
    headless: true,
    slowMo: 0
  ]

  setup_all context do
    global_config = Application.fetch_env!(:phoenix_test, :playwright)
    global_browser_config = List.wrap(global_config[:browser])
    trace = Map.get(context, :trace, global_config[:trace])

    case context do
      %{playwright: true} ->
        opts = Keyword.merge(@playwright_opts, global_browser_config)
        [browser_id: Case.Playwright.launch_browser(opts), trace: trace]

      %{playwright: context_browser_config} when is_list(context_browser_config) ->
        opts =
          @playwright_opts
          |> Keyword.merge(global_browser_config)
          |> Keyword.merge(context_browser_config)

        [browser_id: Case.Playwright.launch_browser(opts), trace: trace]

      _ ->
        :ok
    end
  end

  setup context do
    case context do
      %{playwright: p} when p != false ->
        [conn: Case.Playwright.new_session(context)]

      _ ->
        [conn: Phoenix.ConnTest.build_conn()]
    end
  end

  defmodule Playwright do
    @moduledoc false
    import PhoenixTest.Playwright.Connection

    alias PhoenixTest.Playwright.Browser
    alias PhoenixTest.Playwright.BrowserContext
    alias PhoenixTest.Playwright.Port

    @includes_ecto Code.ensure_loaded?(Ecto.Adapters.SQL.Sandbox) &&
                     Code.ensure_loaded?(Phoenix.Ecto.SQL.Sandbox)

    def launch_browser(opts) do
      ensure_started()
      browser = Keyword.fetch!(opts, :browser)
      browser_id = launch_browser(browser, opts)
      on_exit(fn -> post(guid: browser_id, method: "close") end)
      browser_id
    end

    def new_session(%{browser_id: browser_id} = context) do
      params = if ua = checkout_ecto_repos(context[:async]), do: %{userAgent: ua}, else: %{}
      context_id = Browser.new_context(browser_id, params)
      subscribe(context_id)

      page_id = BrowserContext.new_page(context_id)

      post(%{
        method: :updateSubscription,
        guid: page_id,
        params: %{event: "console", enabled: true}
      })

      frame_id = initializer(page_id).mainFrame.guid
      on_exit(fn -> post(guid: context_id, method: "close") end)

      if trace = context[:trace] do
        BrowserContext.start_tracing(context_id)

        dir =
          :phoenix_test
          |> Application.fetch_env!(:playwright)
          |> Keyword.get(:trace_dir, "tmp")

        File.mkdir_p!(dir)

        "Elixir." <> module = to_string(context.module)
        session_id = System.unique_integer([:positive, :monotonic])

        file =
          String.replace("#{module}.#{context.test}_#{session_id}.zip", ~r/[^a-zA-Z0-9 \.]/, "_")

        path = Path.join(dir, file)

        on_exit(fn ->
          BrowserContext.stop_tracing(context_id, path)

          if trace == :open do
            cli_path = Path.join(File.cwd!(), Port.cli_path())
            System.cmd(cli_path, ["show-trace", path])
          end
        end)
      end

      PhoenixTest.Playwright.build(context_id, page_id, frame_id)
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
        case Ecto.Adapters.SQL.Sandbox.checkout(repo) do
          :ok -> :ok
          {:already, :allowed} -> :ok
        end

        unless async?, do: Ecto.Adapters.SQL.Sandbox.mode(repo, {:shared, self()})

        repo
      end
    else
      def checkout_ecto_repos(_) do
        nil
      end
    end
  end
end
