defmodule PhoenixTest.Playwright.BrowserLaunchTimeoutTest do
  use ExUnit.Case, async: true

  alias PhoenixTest.Playwright.Case, as: PlaywrightCase

  # With websocket transport, the browser is pre-launched on the remote server,
  # so launch timeouts don't apply.
  @moduletag :skip_websocket

  @error_message "You may need to increase the :browser_launch_timeout option"

  for browser_pool <- [:shared, :exclusive] do
    test "#{browser_pool} browser: produces a helpful error when browser_launch_timeout is too small" do
      assert_raise RuntimeError, ~r/#{@error_message}/, fn ->
        PlaywrightCase.do_setup_all(%{browser_pool: unquote(browser_pool), browser_launch_timeout: 1})
      end
    end
  end
end
