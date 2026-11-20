defmodule PhoenixTest.Playwright.CaseTest do
  # Playwright's options pass through, e.g. a context option.
  use PhoenixTest.Playwright.Case, async: true, locale: "de"

  import PhoenixTest.TestHelpers, only: [set_html: 2]

  alias PhoenixTest.Playwright.Config

  describe "screenshot: :on" do
    @tag Playwright.Test.use(screenshot: :on)
    test "saves screenshot on test exit (for verification in CI)", %{conn: conn} do
      conn
      |> set_html("<h1>Screenshot on exit</h1>")
      |> assert_has("h1")
    end
  end

  describe "trace: :on" do
    @tag Playwright.Test.use(trace: :on)
    test "saves trace on test exit (for verification in CI)", %{conn: conn} do
      conn
      |> set_html("<h1>Trace on exit</h1>")
      |> assert_has("h1")
    end
  end

  describe "base_url" do
    # Playwright's resolved `base_url` (config, module, describe or test) wins over phoenix_test's.
    @page_base_url "http://localhost:#{Application.compile_env!(:phoenix_test_playwright, [PhoenixTest.WebApp.Endpoint, :http, :port])}/page/"
    @describetag Playwright.Test.use(base_url: @page_base_url)

    test "from Playwright.Test.use/1 resolves relative paths", %{conn: conn} do
      conn
      |> visit("index")
      |> assert_path("/page/index")
    end

    test "from Playwright.Test.use/1 is the default url of cookies, at its origin", %{conn: conn} do
      assert conn.base_url == @page_base_url
      conn = add_cookies(conn, [[name: "at_origin", value: "1"]])

      assert [%{domain: "localhost", path: "/"}] =
               for(%{name: "at_origin"} = cookie <- Playwright.BrowserContext.cookies!(conn.context), do: cookie)
    end
  end

  describe "context options" do
    test "of the module's use options", %{conn: conn} do
      conn
      |> visit("/pw/headers")
      |> assert_has("#headers", text: "accept-language: de")
    end

    @tag Playwright.Test.use(extra_http_headers: %{"x-custom" => "1"})
    test "of a test", %{conn: conn} do
      conn
      |> visit("/pw/headers")
      |> assert_has("#headers", text: "x-custom: 1")
    end

    @tag Playwright.Test.use(locale: "fr")
    test "of a test win over the module's", %{conn: conn} do
      conn
      |> visit("/pw/headers")
      |> assert_has("#headers", text: "accept-language: fr")
    end

    @tag Playwright.Test.use(viewport: :null)
    test "viewport: :null disables the default viewport", %{conn: conn} do
      refute is_map(Playwright.Page.viewport_size(conn.page))
    end

    test "of new_session/3 win over the resolved ones", context do
      config = context |> Map.take(Config.setup_keys()) |> Config.validate!()

      # `new_session/2` in `setup_all`, without a Playwright `base_url`.
      context
      |> then(&PhoenixTest.Playwright.Case.new_session(config, &1, locale: "it", extra_http_headers: %{"x-setup" => "1"}))
      |> visit("/pw/headers")
      |> assert_has("#headers", text: "accept-language: it")
      |> assert_has("#headers", text: "x-setup: 1")
    end
  end
end

defmodule PhoenixTest.Playwright.CaseSetupAllSessionTest do
  use PhoenixTest.Playwright.Case, async: true

  alias PhoenixTest.Playwright.Config

  setup_all context do
    config = context |> Map.take(Config.setup_keys()) |> Config.validate!()
    [shared_conn: PhoenixTest.Playwright.Case.new_session(config, context)]
  end

  test "new_session/2 in setup_all uses phoenix_test's base_url", %{shared_conn: conn} do
    assert conn.base_url == Application.fetch_env!(:phoenix_test, :base_url)

    conn
    |> visit("/page/index")
    |> assert_path("/page/index")
  end
end

# `new_session/2` and `step/3` in `setup_all`, with the module's `base_url`.
defmodule PhoenixTest.Playwright.CaseSetupAllModuleBaseUrlTest do
  use PhoenixTest.Playwright.Case, async: true

  alias PhoenixTest.Playwright.Config

  @port Application.compile_env!(:phoenix_test_playwright, [PhoenixTest.WebApp.Endpoint, :http, :port])
  @moduletag Playwright.Test.use(base_url: "http://localhost:#{@port}/page/")

  setup_all context do
    config = context |> Map.take(Config.setup_keys()) |> Config.validate!()

    conn =
      config
      |> PhoenixTest.Playwright.Case.new_session(context)
      |> step("Visit in setup_all", &visit(&1, "index"))

    [shared_conn: conn]
  end

  test "new_session/2 in setup_all uses the module's base_url", %{shared_conn: conn} do
    assert conn.base_url == "http://localhost:#{@port}/page/"
    assert_path(conn, "/page/index")
  end
end

# `new_session/2` in `setup_all`, with the project's `base_url`.
defmodule PhoenixTest.Playwright.CaseSetupAllProjectBaseUrlTest do
  use PhoenixTest.Playwright.Case,
    async: true,
    parameterize: [
      Playwright.Test.parameters(
        name: "page",
        base_url:
          "http://localhost:#{Application.compile_env!(:phoenix_test_playwright, [PhoenixTest.WebApp.Endpoint, :http, :port])}/page/"
      )
    ]

  alias PhoenixTest.Playwright.Config

  setup_all context do
    config = context |> Map.take(Config.setup_keys()) |> Config.validate!()
    [shared_conn: PhoenixTest.Playwright.Case.new_session(config, context)]
  end

  test "new_session/2 in setup_all uses the project's base_url", %{shared_conn: conn} do
    conn
    |> visit("index")
    |> assert_path("/page/index")
  end
end

# The Ecto sandbox's metadata follows a configured user agent.
defmodule PhoenixTest.Playwright.CaseUserAgentTest do
  use PhoenixTest.Playwright.Case, async: true, user_agent: "MyBot/1.0"

  @moduletag :capture_log

  test "keeps the configured user agent", %{conn: conn} do
    conn
    |> visit("/pw/headers")
    |> assert_has("#headers", text: "user-agent: MyBot/1.0/BeamMetadata (")
  end

  test "keeps the Ecto sandbox", %{conn: conn} do
    conn
    |> visit("/pw/live/ecto")
    |> assert_has("div", text: "Version: PostgreSQL")
  end
end

defmodule PhoenixTest.Playwright.CaseOptionsTest do
  use ExUnit.Case, async: true

  alias PhoenixTest.Playwright.Config

  test "a removed option raises, naming Playwright's" do
    assert_raise ArgumentError, ~r/the `browser` option .* was removed, use `browser_name`/, fn ->
      Config.reject_removed!(%{module: __MODULE__, browser: :firefox}, "test")
    end

    assert_raise ArgumentError, ~r/`browser_context_opts` .* context options/, fn ->
      Config.reject_removed!(%{module: __MODULE__, browser_context_opts: [locale: "de"]}, "test")
    end
  end

  test "a browser tag of the user's is no removed option" do
    assert :ok = Config.reject_removed!(%{module: __MODULE__, browser: true}, "test")
  end

  test "a removed use option raises, naming Playwright's" do
    assert_raise ArgumentError,
                 ~r/use PhoenixTest.Playwright.Case in .*Firefox: the `browser` option .* `browser_name`/,
                 fn ->
                   Code.compile_string("""
                   defmodule PhoenixTest.Playwright.CaseOptionsTest.Firefox do
                     use PhoenixTest.Playwright.Case, async: true, browser: :firefox
                   end
                   """)
                 end
  end

  test "an unknown use option raises" do
    assert_raise ArgumentError, ~r/unknown option bogus/, fn ->
      Code.compile_string("""
      defmodule PhoenixTest.Playwright.CaseOptionsTest.Bogus do
        use PhoenixTest.Playwright.Case, async: true, bogus: 1
      end
      """)
    end
  end
end

defmodule PhoenixTest.Playwright.CasePlainRecordingTagsTest do
  # Not async: `capture_io(:stderr, ...)` captures every process's stderr.
  use ExUnit.Case, async: false

  alias PhoenixTest.Playwright.Case

  test "plain recording tags warn, as Playwright.Test ignores them" do
    # Warned once per module and key: forget an earlier run's warning.
    :persistent_term.erase({Case, :warned, __MODULE__, :video})

    output =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        Case.warn_plain_recording_tags(%{module: __MODULE__, video: :on})
      end)

    assert output =~ "the plain `video` tag (or parameterize: key) records nothing"
    assert output =~ "Playwright.Test.use(video: ...)"
  end
end
