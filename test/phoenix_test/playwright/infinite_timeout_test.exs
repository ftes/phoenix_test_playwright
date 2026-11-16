defmodule PhoenixTest.Playwright.InfiniteTimeoutTest do
  use PhoenixTest.Playwright.Case, async: true

  test "timeout: :infinity waits without limit", %{conn: conn} do
    # Past the default timeouts, so only `timeout` lets the assertions pass.
    delay = Playwright.Test.config().expect.timeout + 500
    conn = visit(conn, "/page/index", timeout: :infinity)

    conn
    |> evaluate("""
    setTimeout(() => {
      document.body.innerHTML = '<h1>Ready</h1>';
      history.replaceState({}, '', '?ready=true');
    }, #{delay})
    """)
    |> assert_has("h1", text: "Ready", timeout: :infinity)
    |> assert_path("/page/index", query_params: %{ready: true}, timeout: :infinity)
    |> evaluate("setTimeout(() => history.replaceState({}, '', '?ready=false'), #{delay})")
    |> refute_path("/page/index", query_params: %{ready: true}, timeout: :infinity)
  end

  test "an assertion's timeout: 0 checks once", %{conn: conn} do
    conn =
      conn
      |> visit("/page/index")
      |> evaluate("document.body.innerHTML = '<h1>Now</h1>'")

    conn
    |> assert_has("h1", text: "Now", timeout: 0)
    |> refute_has("h2", timeout: 0)
    |> assert_path("/page/index", timeout: 0)
    |> refute_path("/other", timeout: 0)

    conn = evaluate(conn, "setTimeout(() => document.body.innerHTML = '<h2>Later</h2>', 300)")
    assert_raise ExUnit.AssertionError, fn -> assert_has(conn, "h2", timeout: 0) end
    assert_raise ExUnit.AssertionError, fn -> assert_path(conn, "/other", timeout: 0) end
  end

  test "an action's timeout: 0 is rejected", %{conn: conn} do
    assert_raise NimbleOptions.ValidationError, fn -> visit(conn, "/page/index", timeout: 0) end
    assert_raise NimbleOptions.ValidationError, fn -> click(conn, "button", "Submit", timeout: 0) end
    assert_raise NimbleOptions.ValidationError, fn -> assert_screenshot(conn, "x.png", timeout: 0) end
  end
end
