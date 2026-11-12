defmodule PhoenixTest.Playwright.InfiniteTimeoutTest do
  use PhoenixTest.Playwright.Case, async: true

  alias PhoenixTest.Playwright

  for timeout <- [0, :infinity] do
    test "timeout: #{inspect(timeout)} waits without limit", %{conn: conn} do
      timeout = unquote(timeout)
      conn = Playwright.visit(conn, "/page/index", timeout: timeout)

      conn
      |> Playwright.evaluate("""
      setTimeout(() => {
        document.body.innerHTML = '<h1>Ready</h1>';
        history.replaceState({}, '', '?ready=true');
      }, 1000)
      """)
      |> assert_has("h1", text: "Ready", timeout: timeout)
      |> assert_path("/page/index", query_params: %{ready: true}, timeout: timeout)
      |> Playwright.evaluate("setTimeout(() => history.replaceState({}, '', '?ready=false'), 1000)")
      |> refute_path("/page/index", query_params: %{ready: true}, timeout: timeout)
    end
  end
end
