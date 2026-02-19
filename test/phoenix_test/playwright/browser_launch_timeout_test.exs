defmodule PhoenixTest.Playwright.BrowserLaunchTimeoutTest do
  use ExUnit.Case, async: true

  alias PhoenixTest.Playwright.BrowserPool
  alias PhoenixTest.Playwright.Case, as: PlaywrightCase

  @error_message "You may need to increase the :browser_launch_timeout option"

  describe "browser pool launch" do
    test "produces a helpful error when browser_launch_timeout is too small" do
      Process.flag(:trap_exit, true)
      pool = :"pool_timeout_test_#{System.unique_integer([:positive])}"
      BrowserPool.start_link(id: pool, browser_launch_timeout: 1, browser: :chromium)

      {{%RuntimeError{message: message}, _stacktrace}, _} = catch_exit(BrowserPool.checkout(pool))
      assert message =~ @error_message
    end
  end

  describe "direct launch (no pool)" do
    test "produces a helpful error when browser_launch_timeout is too small" do
      assert_raise RuntimeError, ~r/#{@error_message}/, fn ->
        PlaywrightCase.do_setup_all(%{browser_pool: nil, browser_launch_timeout: 1})
      end
    end
  end
end
