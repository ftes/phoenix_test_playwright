defmodule PhoenixTest.Playwright.CaseTest do
  use PhoenixTest.Playwright.Case, async: true

  import PhoenixTest.TestHelpers, only: [set_html: 2]

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
    @tag Playwright.Test.use(base_url: Application.compile_env!(:phoenix_test, :base_url) <> "/page/")
    test "from Playwright.Test.use/1 resolves relative paths", %{conn: conn} do
      conn
      |> visit("index")
      |> assert_path("/page/index")
    end
  end

  setup_all do
    [browser_context_opts: [locale: "de"]]
  end

  describe "browser_context_opts" do
    test "overide locale via setup", %{conn: conn} do
      conn
      |> visit("/pw/headers")
      |> assert_has("#headers", text: "accept-language: de")
    end

    @tag browser_context_opts: [extra_http_headers: %{"x-custom" => "1"}]
    test "accepts extra_http_headers as a map", %{conn: conn} do
      conn
      |> visit("/pw/headers")
      |> assert_has("#headers", text: "x-custom: 1")
    end

    @tag browser_context_opts: %{locale: "fr"}
    test "accepts a map", %{conn: conn} do
      conn
      |> visit("/pw/headers")
      |> assert_has("#headers", text: "accept-language: fr")
    end

    test "rejects a map with string keys" do
      assert_raise NimbleOptions.ValidationError, ~r/browser_context_opts/, fn ->
        PhoenixTest.Playwright.Config.validate!(browser_context_opts: %{"locale" => "fr"})
      end
    end

    @tag browser_context_opts: [viewport: :null]
    test "viewport: :null disables the default viewport", %{conn: conn} do
      refute is_map(Playwright.Page.viewport_size(conn.page))
    end
  end
end
