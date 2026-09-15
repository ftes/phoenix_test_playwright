defmodule PhoenixTest.Playwright.TimeoutTest do
  use ExUnit.Case, async: true

  alias PhoenixTest.Playwright
  alias PhoenixTest.Playwright.Config

  test "configuration accepts zero, finite, and infinite timeouts, including pools" do
    for timeout <- [0, 100, :infinity] do
      config =
        Config.validate!(
          timeout: timeout,
          browser_launch_timeout: timeout,
          browser_pool_checkout_timeout: timeout,
          browser_pools: [[id: :test_pool, browser_launch_timeout: timeout]]
        )

      assert config[:timeout] == timeout
      assert config[:browser_launch_timeout] == timeout
      assert config[:browser_pool_checkout_timeout] == timeout
      assert hd(config[:browser_pools])[:browser_launch_timeout] == timeout
    end
  end

  test "configuration rejects invalid timeouts" do
    for key <- [:timeout, :browser_launch_timeout, :browser_pool_checkout_timeout], value <- [-1, :forever] do
      assert_raise NimbleOptions.ValidationError, fn -> Config.validate!([{key, value}]) end
    end
  end

  test "infinite retries continue after failed assertions" do
    Process.put(:attempts, 0)

    assert :ready ==
             Playwright.retry(
               fn ->
                 attempt = Process.get(:attempts) + 1
                 Process.put(:attempts, attempt)
                 assert attempt == 3
                 :ready
               end,
               :infinity
             )

    assert Process.get(:attempts) == 3
  end

  test "zero checks once and finite retries still expire" do
    for {timeout, attempts} <- [{0, 1}, {20, 3}] do
      Process.put(:attempts, 0)

      assert_raise ExUnit.AssertionError, fn ->
        Playwright.retry(
          fn ->
            Process.put(:attempts, Process.get(:attempts) + 1)
            flunk("not ready")
          end,
          timeout
        )
      end

      assert Process.get(:attempts) == attempts
    end
  end

  test "infinite retries do not catch unexpected errors" do
    assert_raise ArgumentError, "unexpected", fn ->
      Playwright.retry(fn -> raise ArgumentError, "unexpected" end, :infinity)
    end
  end
end
