defmodule PhoenixTest.Playwright.FirefoxTest do
  use PhoenixTest.Playwright.Case, async: true, browser_pool: :firefox_pool

  test "uses firefox browser from pool", %{conn: conn} do
    conn
    |> visit("/pw/live/index")
    |> assert_has("h1")
  end
end
