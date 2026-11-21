defmodule PhoenixTest.Playwright.FirefoxTest do
  use PhoenixTest.Playwright.Case,
    async: true,
    browser_name: :firefox

  import PhoenixTest.TestHelpers, only: [set_html: 2]

  test "uses a firefox browser", %{conn: conn, playwright_browser: browser} do
    assert browser |> Playwright.Browser.browser_type() |> Playwright.BrowserType.name() == "firefox"

    conn
    |> set_html("<h1>Firefox</h1>")
    |> assert_has("h1")
  end
end
