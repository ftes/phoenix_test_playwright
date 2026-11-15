defmodule PhoenixTest.Playwright.InfiniteTimeoutTest do
  use PhoenixTest.Playwright.Case, async: true

  alias PhoenixTest.Playwright

  test "timeout: :infinity waits without limit", %{conn: conn} do
    # Past the default timeouts, so only `timeout` lets the assertions pass.
    delay = PlaywrightEx.Test.config().expect.timeout + 500
    conn = Playwright.visit(conn, "/page/index", timeout: :infinity)

    conn
    |> Playwright.evaluate("""
    setTimeout(() => {
      document.body.innerHTML = '<h1>Ready</h1>';
      history.replaceState({}, '', '?ready=true');
    }, #{delay})
    """)
    |> assert_has("h1", text: "Ready", timeout: :infinity)
    |> assert_path("/page/index", query_params: %{ready: true}, timeout: :infinity)
    |> Playwright.evaluate("setTimeout(() => history.replaceState({}, '', '?ready=false'), #{delay})")
    |> refute_path("/page/index", query_params: %{ready: true}, timeout: :infinity)
  end

  test "an assertion's timeout: 0 checks once", %{conn: conn} do
    conn =
      conn
      |> Playwright.visit("/page/index")
      |> Playwright.evaluate("document.body.innerHTML = '<h1>Now</h1>'")

    conn
    |> assert_has("h1", text: "Now", timeout: 0)
    |> refute_has("h2", timeout: 0)
    |> assert_path("/page/index", timeout: 0)
    |> refute_path("/other", timeout: 0)

    conn = Playwright.evaluate(conn, "setTimeout(() => document.body.innerHTML = '<h2>Later</h2>', 300)")
    assert_raise ExUnit.AssertionError, fn -> assert_has(conn, "h2", timeout: 0) end
    assert_raise ExUnit.AssertionError, fn -> assert_path(conn, "/other", timeout: 0) end
  end

  test "an action's timeout: 0 is rejected", %{conn: conn} do
    assert_raise NimbleOptions.ValidationError, fn -> Playwright.visit(conn, "/page/index", timeout: 0) end
    assert_raise NimbleOptions.ValidationError, fn -> Playwright.click(conn, "button", "Submit", timeout: 0) end
    assert_raise NimbleOptions.ValidationError, fn -> Playwright.assert_screenshot(conn, "x.png", timeout: 0) end
  end
end
