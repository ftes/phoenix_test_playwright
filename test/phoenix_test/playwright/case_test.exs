defmodule PhoenixTest.Playwright.CaseTest do
  use PhoenixTest.Playwright.Case, async: true

  describe "@tag :screenshot" do
    @tag :screenshot
    test "saves screenshot on test exit (for verification in CI)", %{conn: conn} do
      conn
      |> visit("/pw/live")
      |> assert_has("h1")
    end
  end

  describe "@tag :trace" do
    if Application.compile_env!(:phoenix_test, :playwright)[:ws_endpoint],
      do: @describetag(skip: "FIXME Accessing trace from remote server")

    @tag :trace
    test "saves trace on test exit (for verification in CI)", %{conn: conn} do
      conn
      |> visit("/pw/live")
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
