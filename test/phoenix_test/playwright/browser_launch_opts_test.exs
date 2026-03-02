defmodule PhoenixTest.Playwright.BrowserLaunchOptsTest do
  @moduledoc """
  Tests that browser_launch_opts are passed through to Playwright.
  """

  use PhoenixTest.Playwright.Case,
    async: true,
    browser_pool: false,
    browser_launch_opts: [args: ["--disable-background-networking"]]

  test "launches browser with custom launch opts", %{conn: conn} do
    # Verifies that browser_launch_opts is accepted by the config and doesn't
    # break browser launching. The args are passed through to Playwright.
    conn
    |> visit("/pw/live")
    |> assert_has("h1")
  end
end
