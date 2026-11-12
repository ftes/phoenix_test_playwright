defmodule PhoenixTest.Playwright.MultipleBrowsersParameterizeTest do
  use PhoenixTest.Playwright.Case,
    async: true,
    parameterize: [%{browser: :chromium}, %{browser: :firefox}]

  import PhoenixTest.TestHelpers, only: [set_html: 2]

  test "run the same test in multiple browsers ", %{conn: conn} do
    conn
    |> set_html("<h1>Parameterized browser</h1>")
    |> assert_has("h1")
  end
end
