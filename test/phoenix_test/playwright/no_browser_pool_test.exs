defmodule PhoenixTest.Playwright.NoBrowserPoolTest do
  use PhoenixTest.Playwright.Case, async: true, browser_pool: false

  test "launches new browser instead of checking out from pool", %{conn: conn} do
    conn
    |> visit("/pw/live")
    |> assert_has("h1")
  end
end
