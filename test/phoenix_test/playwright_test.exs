defmodule PhoenixTest.PlaywrightTest do
  @moduledoc """
  Tests for non-phoenix_test-standard behaviour.
  Standard behaviour should instead be covered by `./upstream` tests.
  """

  use PhoenixTest.Playwright.Case, async: true

  import ExUnit.CaptureLog, only: [capture_log: 1]

  alias PlaywrightEx.Selector

  describe "screenshot/3" do
    setup %{conn: conn} do
      [conn: conn |> visit("/pw/longer-than-viewport") |> assert_has("h1", text: "Longer than viewport")]
    end

    test "takes a screenshot of the current page as a PNG", %{conn: conn} do
      name = "png_#{:erlang.system_time(:second)}.png"
      screenshot(conn, name, full_page: false, omit_background: true)
      assert File.exists?("screenshots/#{name}")
    end

    test "takes a screenshot of the current page as a JPEG", %{conn: conn} do
      name = "jpg_#{:erlang.system_time(:second)}.jpg"
      screenshot(conn, name)
      assert File.exists?("screenshots/#{name}")
    end

    test "full page screenshots are larger in file size than non-full-page", %{conn: conn} do
      full_page_name = "full_page_#{:erlang.system_time(:second)}.png"
      viewport_name = "viewport_#{:erlang.system_time(:second)}.png"

      conn
      |> screenshot(full_page_name, full_page: true)
      |> screenshot(viewport_name, full_page: false)

      assert {:ok, %File.Stat{size: full_page_size}} = File.stat("screenshots/#{full_page_name}")
      assert {:ok, %File.Stat{size: viewport_size}} = File.stat("screenshots/#{viewport_name}")

      assert full_page_size > viewport_size
    end
  end

  describe "browser dialog handling: accept_dialogs config and with_dialog/3" do
    test "accepts dialog by default", %{conn: conn} do
      conn
      |> visit("/pw/live")
      |> click_link("Confirm to navigate")
      |> assert_path("/pw/other")
    end

    @tag accept_dialogs: false
    test "override config via tag: dismisses dialog and fails click_link", %{conn: conn} do
      assert_raise ArgumentError, fn ->
        conn
        |> visit("/pw/live")
        |> click_link("Confirm to navigate")
      end
    end

    @tag accept_dialogs: false
    test "with_dialog/3 accepts dialog conditionally", %{conn: conn} do
      conn
      |> visit("/pw/live")
      |> assert_has("h1", text: "Playwright")
      |> with_dialog(
        fn %{message: "Are you sure?"} -> :accept end,
        fn conn ->
          conn
          |> click_link("Confirm to navigate")
          |> assert_path("/pw/other")
        end
      )
    end
  end

  describe "open_browser" do
    setup do
      open_fun = fn path ->
        html = path |> File.read!() |> LazyHTML.from_document()
        [css_href] = html |> LazyHTML.query("link[rel=stylesheet]") |> LazyHTML.attribute("href")
        assert css_href =~ "phoenix_test_playwright\/priv\/static\/assets\/app\.css"

        path
      end

      %{open_fun: open_fun}
    end

    test "opens the browser ", %{conn: conn, open_fun: open_fun} do
      conn
      |> visit("/pw/live")
      |> open_browser(open_fun)
      |> assert_has("h1", text: "Playwright")
    end
  end

  describe "unwrap" do
    test "provides an escape hatch that gives access to the underlying frame", %{conn: conn} do
      conn
      |> visit("/pw/live")
      |> unwrap(fn %{frame_id: frame_id} ->
        selector = Selector.role("link", "Navigate", exact: true)
        {:ok, _} = PlaywrightEx.Frame.click(frame_id, selector: selector, timeout: timeout())
      end)
      |> assert_has("h1", text: "Other")
    end
  end

  describe "type/3" do
    test "fills in a single text field based on the label", %{conn: conn} do
      conn
      |> visit("/pw/live")
      |> type("#text-input", "My text")
      |> assert_has("#changed-form-data", text: "text: My text")
    end
  end

  describe "press/3" do
    test "submits a form via Enter key", %{conn: conn} do
      conn
      |> visit("/pw/live")
      |> type("#text-input", "My text")
      |> press("#text-input", "Enter")
      |> assert_has("#submitted-form-data", text: "text: My text")
    end
  end

  describe "drag/3" do
    test "triggers a javascript event handler", %{conn: conn} do
      conn
      |> visit("/pw/live")
      |> refute_has("#drag-status", text: "dropped")
      |> drag(Selector.text("Drag this"), to: Selector.text("Drop here"))
      |> assert_has("#drag-status", text: "dropped")
    end
  end

  describe "add_cookies/2" do
    test "sets a plain cookie", %{conn: conn} do
      conn
      |> add_cookies([[name: "name", value: "42"]])
      |> visit("/pw/cookies")
      |> assert_has("#cookies", text: "name: 42")
    end

    test "sets an encrypted cookie", %{conn: conn} do
      conn
      |> add_cookies([[name: "name", value: "42", encrypt: true]])
      |> visit("/pw/cookies?encrypted[]=")
      |> assert_has("#cookies", text: "name:")
      |> refute_has("#cookies", text: "name: 42")

      conn
      |> add_cookies([[name: "name", value: "42", encrypt: true]])
      |> visit("/pw/cookies?encrypted[]=name")
      |> assert_has("#cookies", text: "name: 42")
    end

    test "sets a signed cookie", %{conn: conn} do
      conn
      |> add_cookies([[name: "name", value: "42", sign: true]])
      |> visit("/pw/cookies?signed[]=")
      |> assert_has("#cookies", text: "name:")
      |> refute_has("#cookies", text: "name: 42")

      conn
      |> add_cookies([[name: "name", value: "42", sign: true]])
      |> visit("/pw/cookies?signed[]=name")
      |> assert_has("#cookies", text: "name: 42")
    end
  end

  describe "add_session_cookie/3" do
    test "puts a signed, encrypted cookie on the Conn", %{conn: conn} do
      cookie = [value: %{secret: "monty_python"}]

      conn
      |> add_session_cookie(cookie, PhoenixTest.Endpoint.session_options())
      |> visit("/pw/session")
      |> assert_has("#session", text: "secret: monty_python")
    end
  end

  describe "clear_cookies/2" do
    test "removes all cookies", %{conn: conn} do
      conn
      |> add_cookies([[name: "name", value: "42"]])
      |> visit("/pw/cookies")
      |> assert_has("#cookies", text: "name: 42")
      |> clear_cookies()
      |> visit("/pw/cookies")
      |> refute_has("#cookies", text: "name: 42")
    end
  end

  describe "javascript logs" do
    test "logs file and line number", %{conn: conn} do
      log =
        capture_log(fn ->
          visit(conn, "/pw/js-script-console-error")
        end)

      assert log =~ "TESTME 42 (#{Application.get_env(:phoenix_test, :base_url)}/pw/js-script-console-error:16)"
    end

    test "logs without location if unknown", %{conn: conn} do
      log =
        capture_log(fn ->
          conn
          |> visit("/pw/live")
          |> tap(&PlaywrightEx.Frame.evaluate(&1.frame_id, expression: "console.error('TESTME 42')", timeout: timeout()))
        end)

      assert log =~ "TESTME 42"
      refute log =~ "localhost"
    end
  end
end
