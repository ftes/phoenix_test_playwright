defmodule PhoenixTest.PlaywrightBrowserPoolTest do
  use PhoenixTest.Playwright.Case,
    async: true,
    browser_pool: :chromium,
    parameterize: Enum.map(1..100, &%{index: &1})

  test "navigates to page", %{conn: conn} do
    conn
    |> visit("/page/index")
    |> assert_has("h1", text: "Main page")
  end
end
