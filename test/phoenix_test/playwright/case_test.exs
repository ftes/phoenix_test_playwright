defmodule PhoenixTest.Playwright.CaseTest do
  use PhoenixTest.Playwright.Case, async: true

  import PhoenixTest.TestHelpers, only: [set_html: 2]

  describe "@tag :screenshot" do
    @tag :screenshot
    test "saves screenshot on test exit (for verification in CI)", %{conn: conn} do
      conn
      |> set_html("<h1>Screenshot on exit</h1>")
      |> assert_has("h1")
    end
  end

  describe "@tag :trace" do
    @tag :trace
    test "saves trace on test exit (for verification in CI)", %{conn: conn} do
      conn
      |> set_html("<h1>Trace on exit</h1>")
      |> assert_has("h1")
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
  end
end
