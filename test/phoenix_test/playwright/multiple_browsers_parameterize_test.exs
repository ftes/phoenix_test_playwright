defmodule PhoenixTest.Playwright.MultipleBrowsersParameterizeTest do
  use PhoenixTest.Playwright.Case,
    async: true,
    parameterize: [%{browser_pool: :chromium_pool}, %{browser_pool: :firefox_pool}]

  test "run the same test in multiple browsers (checkout from pools)", %{conn: conn} do
    conn
    |> visit("/pw/live/index")
    |> assert_has("h1")
  end
end
