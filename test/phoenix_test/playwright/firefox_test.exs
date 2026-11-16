defmodule PhoenixTest.Playwright.FirefoxTest do
  use PhoenixTest.Playwright.Case,
    async: true,
    browser: :firefox

  import PhoenixTest.TestHelpers, only: [set_html: 2]

  test "uses a firefox browser", %{conn: conn} do
    conn
    |> set_html("<h1>Firefox</h1>")
    |> assert_has("h1")
  end
end
