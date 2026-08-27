defmodule PhoenixTest.Playwright.FirefoxTest do
  use PhoenixTest.Playwright.Case, async: true, browser_pool: :firefox_pool

  import PhoenixTest.TestHelpers, only: [set_html: 2]

  test "uses firefox browser from pool", %{conn: conn} do
    conn
    |> set_html("<h1>Firefox</h1>")
    |> assert_has("h1")
  end
end
