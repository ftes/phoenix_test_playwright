defmodule PhoenixTest.Playwright.NoBrowserPoolTest do
  use PhoenixTest.Playwright.Case, async: true, browser_pool: false

  import PhoenixTest.TestHelpers, only: [set_html: 2]

  test "launches new browser instead of checking out from pool", %{conn: conn} do
    conn
    |> set_html("<h1>New browser</h1>")
    |> assert_has("h1")
  end
end
