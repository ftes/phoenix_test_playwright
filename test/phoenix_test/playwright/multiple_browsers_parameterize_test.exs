defmodule PhoenixTest.Playwright.MultipleBrowsersParameterizeTest do
  use PhoenixTest.Playwright.Case,
    async: true,
    parameterize: [
      Playwright.Test.parameters(name: "chromium", browser_name: :chromium),
      Playwright.Test.parameters(name: "firefox", browser_name: :firefox)
    ]

  import PhoenixTest.TestHelpers, only: [set_html: 2]

  test "run the same test in multiple browsers ", %{conn: conn, playwright_browser: browser} = context do
    # Each project is named after its browser.
    assert browser |> Playwright.Browser.browser_type() |> Playwright.BrowserType.name() ==
             context[:"playwright.project"].name

    conn
    |> set_html("<h1>Parameterized browser</h1>")
    |> assert_has("h1")
  end
end
