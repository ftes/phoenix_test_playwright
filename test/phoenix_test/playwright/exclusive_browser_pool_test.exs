defmodule PhoenixTest.Playwright.ExclusiveBrowserPoolTest do
  use PhoenixTest.Playwright.Case, async: true, browser_pool: :exclusive

  import PhoenixTest.TestHelpers, only: [set_html: 2]

  test "uses a browser held by this module", %{conn: conn} do
    conn
    |> set_html("<h1>Exclusive browser</h1>")
    |> assert_has("h1")
  end
end
