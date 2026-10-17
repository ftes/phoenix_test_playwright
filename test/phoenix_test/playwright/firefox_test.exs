defmodule PhoenixTest.Playwright.FirefoxTest do
  use PhoenixTest.Playwright.Case,
    async: true,
    browser_pool: :firefox_pool,
    # Firefox context creation can exceed the default 500ms test timeout under load
    browser_context_opts: [timeout: 5_000]

  import PhoenixTest.TestHelpers, only: [set_html: 2]

  test "uses firefox browser from pool", %{conn: conn} do
    conn
    |> set_html("<h1>Firefox</h1>")
    |> assert_has("h1")
  end
end
