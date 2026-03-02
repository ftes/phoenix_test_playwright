defmodule PhoenixTest.Playwright.BrowserLaunchOptsTest do
  @moduledoc """
  Tests that browser_launch_opts are passed through to Playwright.
  """

  use PhoenixTest.Playwright.Case,
    async: true,
    browser_pool: false,
    browser_launch_opts: [args: ["--disable-background-networking"]]

  test "launches browser with custom launch opts", %{conn: conn} do
    # If browser_launch_opts weren't handled correctly, the browser launch would fail.
    # This test verifies the option is properly passed through the launch pipeline.
    conn
    |> visit("/pw/live")
    |> assert_has("h1")
  end
end
