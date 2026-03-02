defmodule PhoenixTest.Playwright.BrowserLaunchOptsTest do
  @moduledoc """
  Tests that browser_launch_opts are passed through to Playwright.

  These tests verify that browser launch flags actually affect browser behavior
  by testing getUserMedia with and without fake media device flags.
  """

  use PhoenixTest.Playwright.Case,
    async: true,
    browser_pool: false,
    browser_launch_opts: [
      args: [
        "--use-fake-ui-for-media-stream",
        "--use-fake-device-for-media-stream"
      ]
    ]

  test "getUserMedia succeeds with fake media device flags", %{conn: conn} do
    conn
    |> visit("/pw/live")
    |> assert_has("h1")
    |> unwrap(fn %{frame_id: frame_id} ->
      {:ok, result} =
        PlaywrightEx.Frame.evaluate(frame_id,
          expression: """
            navigator.mediaDevices.getUserMedia({ audio: true })
              .then(() => "success")
              .catch(e => "error: " + e.name)
          """,
          timeout: timeout()
        )

      assert result == "success"
    end)
  end
end

defmodule PhoenixTest.Playwright.BrowserLaunchOptsWithoutFlagsTest do
  @moduledoc """
  Tests that getUserMedia fails WITHOUT the fake media device flags.
  This proves the flags in BrowserLaunchOptsTest actually have an effect.
  """

  use PhoenixTest.Playwright.Case,
    async: true,
    browser_pool: false

  test "getUserMedia fails without fake media device flags", %{conn: conn} do
    conn
    |> visit("/pw/live")
    |> assert_has("h1")
    |> unwrap(fn %{frame_id: frame_id} ->
      {:ok, result} =
        PlaywrightEx.Frame.evaluate(frame_id,
          expression: """
            navigator.mediaDevices.getUserMedia({ audio: true })
              .then(() => "success")
              .catch(e => "error: " + e.name)
          """,
          timeout: timeout()
        )

      # Without fake device flags, getUserMedia should fail in headless mode
      assert result =~ "error:"
    end)
  end
end
