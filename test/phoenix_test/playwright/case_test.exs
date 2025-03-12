defmodule PhoenixTest.Playwright.CaseTest do
  use PhoenixTest.Playwright.Case, async: true

  alias PhoenixTest.Playwright.Connection

  describe "@tag :screenshot" do
    @tag :screenshot
    test "saves screenshot on test exit (for verification in CI)", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> assert_has("h1")
    end
  end

  describe "@tag :trace" do
    @tag :trace
    test "saves trace on test exit (for verification in CI)", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> assert_has("h1")
    end
  end

  setup_all context do
    context_id = PhoenixTest.Playwright.Browser.new_context(context.browser_id)
    page_id = PhoenixTest.Playwright.BrowserContext.new_page(context_id)
    frame_id = Connection.initializer(page_id).main_frame.guid
    session = PhoenixTest.Playwright.build(context_id, page_id, frame_id)
    visit(session, "/page/cookie_counter")
    %{result: %{cookies: cookies}} = Connection.post(guid: context_id, method: :cookies, params: %{urls: []})
    Connection.post(guid: context_id, method: :close)

    [cookies: cookies]
  end

  test "reuse cookies", %{conn: conn, cookies: cookies} do
    conn
    |> visit("/page/cookie_counter")
    |> assert_has("#form-data", text: "counter's value is empty")

    Connection.post(guid: conn.context_id, method: :add_cookies, params: %{cookies: cookies})

    conn
    |> visit("/page/cookie_counter")
    |> assert_has("#form-data", text: "counter: 1")
  end
end
