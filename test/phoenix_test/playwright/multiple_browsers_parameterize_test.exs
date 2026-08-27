defmodule PhoenixTest.Playwright.MultipleBrowsersParameterizeTest do
  use PhoenixTest.Playwright.Case,
    async: true,
    parameterize: [%{browser_pool: :chromium_pool}, %{browser_pool: :firefox_pool}]

  import PhoenixTest.TestHelpers, only: [set_html: 2]

  test "run the same test in multiple browsers (checkout from pools)", %{conn: conn} do
    conn
    |> set_html("<h1>Parameterized browser</h1>")
    |> assert_has("h1")
  end
end
