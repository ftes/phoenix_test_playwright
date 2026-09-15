defmodule PhoenixTest.Playwright.InfiniteTimeoutTest do
  # Global configuration is changed before session setup, so these tests run serially.
  use ExUnit.Case, async: false

  import PhoenixTest
  import PhoenixTest.TestHelpers, only: [set_html: 2]

  alias PhoenixTest.Playwright
  alias PhoenixTest.Playwright.Case, as: PlaywrightCase

  setup context do
    original = Application.fetch_env!(:phoenix_test, :playwright)

    config =
      Keyword.merge(original,
        timeout: :infinity,
        browser_launch_timeout: :infinity,
        browser_pool_checkout_timeout: :infinity
      )

    Application.put_env(:phoenix_test, :playwright, config)
    on_exit(fn -> Application.put_env(:phoenix_test, :playwright, original) end)

    context = Map.merge(context, Map.new(PlaywrightCase.do_setup_all(context)))
    PlaywrightCase.do_setup(context)
  end

  @tag browser_pool: false
  test "global infinity covers browser launch, commands, assertions, and download saves", %{conn: conn} do
    download_url = Application.fetch_env!(:phoenix_test, :base_url) <> "/pw/download"

    conn
    |> set_html("""
    <button onclick="document.querySelector('h1').textContent = 'Ready'">Continue</button>
    <h1>Waiting</h1>
    <a href="#{download_url}">Download</a>
    """)
    |> click_button("Continue")
    |> assert_has("h1", text: "Ready")
    |> click_link("Download")
    |> Playwright.assert_download(fn download -> assert byte_size(download.content) > 0 end)
  end

  test "per-operation infinity waits for browser assertions and path changes", %{conn: conn} do
    conn = Playwright.visit(conn, "/page/index", timeout: :infinity)

    conn
    |> Playwright.evaluate(
      """
      setTimeout(() => {
        document.body.innerHTML = '<h1>Ready</h1>';
        history.replaceState({}, '', '?ready=true');
      }, 50)
      """,
      timeout: :infinity
    )
    |> assert_has("h1", text: "Ready", timeout: :infinity)
    |> assert_path("/page/index", query_params: %{ready: true}, timeout: :infinity)
    |> Playwright.evaluate("setTimeout(() => history.replaceState({}, '', '?ready=false'), 50)")
    |> refute_path("/page/index", query_params: %{ready: true}, timeout: :infinity)
  end
end
