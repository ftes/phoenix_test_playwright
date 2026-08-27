defmodule PhoenixTest.PlaywrightTest do
  @moduledoc """
  Tests for non-phoenix_test-standard behaviour.
  Standard behaviour should instead be covered by `./upstream` tests.
  """

  use PhoenixTest.Playwright.Case, async: true

  import ExUnit.CaptureLog, only: [capture_log: 1]
  import PhoenixTest.TestHelpers, only: [set_html: 2]

  alias PlaywrightEx.Selector

  @long_page_html "<h1>Longer than viewport</h1>" <> String.duplicate("<div>Lorem ipsum</div>", 100)

  @screenshot_html """
  <h1>Screenshot fixture</h1>
  <p id="sibling" style="background: yellow">Sibling content</p>
  """

  describe "screenshot/3" do
    setup %{conn: conn} do
      [conn: conn |> set_html(@long_page_html) |> assert_has("h1", text: "Longer than viewport")]
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

  describe "assert_screenshot/3" do
    setup %{conn: conn} do
      [conn: set_html(conn, @screenshot_html)]
    end

    @tag :tmp_dir
    test "captures baseline on first run and writes file", %{conn: conn, tmp_dir: tmp_dir} do
      assert_screenshot(conn, "capture.png", snapshot_dir: tmp_dir)
      assert File.exists?(Path.join(tmp_dir, "capture.png"))
    end

    test "passes silently when screenshot matches baseline", %{conn: conn} do
      # Add max_diff_pixel_ratio to account for different font locally vs CI
      assert_screenshot(conn, "baseline.png", max_diff_pixel_ratio: 0.01)
    end

    test "raises when screenshot does not match baseline", %{conn: conn} do
      assert_raise ExUnit.AssertionError,
                   ~r"Screenshot mismatch for baseline\.png: \d+ pixels \(ratio \d+(?:\.\d+)? of all image pixels\) are different\.",
                   fn ->
                     conn
                     |> set_html("<h1>Different screenshot</h1>")
                     |> assert_screenshot("baseline.png")
                   end

      on_exit(fn -> File.rm!("test/snapshots/__diff__/baseline.png") end)
    end

    @tag :tmp_dir
    test "raises on invalid clip option", %{conn: conn, tmp_dir: tmp_dir} do
      assert_raise ExUnit.AssertionError,
                   ~r"Expected options.clip.width to be greater than 0.",
                   fn ->
                     assert_screenshot(conn, "clip.png",
                       snapshot_dir: tmp_dir,
                       clip: %{x: 0, y: 0, width: 0, height: 100}
                     )
                   end
    end

    @tag :tmp_dir
    test "creates subdirectory for nested name", %{conn: conn, tmp_dir: tmp_dir} do
      assert_screenshot(conn, "subdir/nested.png", snapshot_dir: tmp_dir)
      assert File.exists?(Path.join(tmp_dir, "subdir/nested.png"))
    end

    @tag :tmp_dir
    test "scopes screenshot to element when selector opt is given", %{conn: conn, tmp_dir: tmp_dir} do
      assert_screenshot(conn, "selector.png", selector: "h1", snapshot_dir: tmp_dir)

      # Change the color of a sibling element — full-page screenshot would differ, but scoped to h1 it still matches
      conn
      |> evaluate("document.querySelector('#sibling').style.backgroundColor = 'blue'")
      |> assert_screenshot("selector.png", selector: "h1", snapshot_dir: tmp_dir)
    end

    @tag :tmp_dir
    test "masks elements so changes within them don't cause mismatch", %{conn: conn, tmp_dir: tmp_dir} do
      assert_screenshot(conn, "mask.png", mask: ["h1"], snapshot_dir: tmp_dir)

      # Change the h1 text — masked element differs, but screenshot still matches
      conn
      |> evaluate("document.querySelector('h1').textContent = 'changed'")
      |> assert_screenshot("mask.png", mask: ["h1"], snapshot_dir: tmp_dir)
    end

    @tag :tmp_dir
    test "writes diff file when mismatch produces a diff image", %{conn: conn, tmp_dir: tmp_dir} do
      assert_screenshot(conn, "diff.png", selector: "h1", snapshot_dir: tmp_dir)

      assert_raise ExUnit.AssertionError,
                   ~r/Screenshot mismatch for diff\.png: \d+ pixels \(ratio \d+(?:\.\d+)? of all image pixels\) are different./,
                   fn ->
                     conn
                     |> evaluate("document.querySelector('h1').style.color = 'red'")
                     |> assert_screenshot("diff.png", selector: "h1", snapshot_dir: tmp_dir)
                   end

      assert File.exists?(Path.join([tmp_dir, "__diff__", "diff.png"]))
    end

    test "raises without writing diff when comparison times out", %{conn: conn} do
      assert_raise ExUnit.AssertionError, ~r"Timeout 1ms exceeded.", fn ->
        conn
        |> set_html("<h1>Different screenshot</h1>")
        |> assert_screenshot("baseline.png", timeout: 1)
      end

      refute File.exists?("test/snapshots/__diff__/baseline.png")
    end
  end

  describe "browser dialog handling: accept_dialogs config and with_dialog/3" do
    @dialog_html """
    <a href="#accepted" onclick="return confirm('Are you sure?')">Confirm to navigate</a>
    <p id="accepted">Accepted</p>
    """

    test "accepts dialog by default", %{conn: conn} do
      conn
      |> set_html(@dialog_html)
      |> click_link("Confirm to navigate")
      |> assert_has("#accepted:target")
    end

    @tag accept_dialogs: false
    test "override config via tag: dismisses dialog and fails click_link", %{conn: conn} do
      assert_raise ArgumentError, fn ->
        conn
        |> set_html(@dialog_html)
        |> click_link("Confirm to navigate")
      end
    end

    @tag accept_dialogs: false
    test "with_dialog/3 accepts dialog conditionally", %{conn: conn} do
      conn
      |> set_html(@dialog_html)
      |> with_dialog(
        fn %{message: "Are you sure?"} -> :accept end,
        fn conn ->
          conn
          |> click_link("Confirm to navigate")
          |> assert_has("#accepted:target")
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
      |> set_html("""
      <link rel="stylesheet" href="/assets/app.css" />
      <h1>Playwright</h1>
      """)
      |> open_browser(open_fun)
      |> assert_has("h1", text: "Playwright")
    end
  end

  describe "assertion option validation" do
    test "raises for unsupported assert_has/refute_has options", %{conn: conn} do
      session = set_html(conn, "<h1>Playwright</h1>")

      assert_raise NimbleOptions.ValidationError, ~r/unknown.*:playwright/, fn ->
        assert_has(session, "h1", playwright: [strict: false])
      end

      assert_raise NimbleOptions.ValidationError, ~r/unknown.*:playwright/, fn ->
        refute_has(session, "h1", playwright: [strict: false])
      end
    end

    test "raises for unsupported public API options", %{conn: conn} do
      session =
        set_html(conn, """
        <label for="text-input">Text input</label>
        <input id="text-input" />
        <label for="select-input">Select input</label>
        <select id="select-input"><option>One</option></select>
        """)

      assert_raise NimbleOptions.ValidationError, ~r/unknown.*:bogus/, fn ->
        PhoenixTest.Playwright.reload_page(session, bogus: true)
      end

      assert_raise NimbleOptions.ValidationError, ~r/unknown.*:bogus/, fn ->
        assert_path(session, "/", bogus: true)
      end

      assert_raise NimbleOptions.ValidationError, ~r/unknown.*:bogus/, fn ->
        PhoenixTest.Playwright.fill_in(session, "Text input", with: "value", bogus: true)
      end

      assert_raise NimbleOptions.ValidationError, ~r/unknown.*:bogus/, fn ->
        PhoenixTest.Playwright.select(session, "One", from: "Select input", bogus: true)
      end
    end
  end

  describe "assert_has/3 visibility" do
    test "finds visible text when a hidden text match appears first", %{conn: conn} do
      conn
      |> set_html("""
      <div id="hidden-text-repro">
        <span hidden>Text to find</span>
        <span class="visible">Text to find</span>
      </div>
      """)
      |> assert_has("#hidden-text-repro .visible", text: "Text to find")
      |> assert_has("#hidden-text-repro", text: "Text to find")
      |> assert_has("#hidden-text-repro", text: "Text to find", count: 1)
    end
  end

  describe "click/3" do
    test "clicks the selector when it contains duplicate visible and hidden text", %{conn: conn} do
      conn
      |> set_html("""
      <table id="hidden-duplicate-click-repro">
        <tr>
          <td onclick="document.getElementById('hidden-duplicate-click-status').textContent = 'clicked'">
            <div>Changed by production</div>
            <div hidden><div>Changed by production</div></div>
          </td>
        </tr>
      </table>
      <div id="hidden-duplicate-click-status">pending</div>
      """)
      |> click("#hidden-duplicate-click-repro td", "Changed by production")
      |> assert_has("#hidden-duplicate-click-status", text: "clicked")
      |> evaluate("document.getElementById('hidden-duplicate-click-status').textContent = 'pending'")
      |> click("#hidden-duplicate-click-repro td", "Changed by production", exact: true)
      |> assert_has("#hidden-duplicate-click-status", text: "clicked")
    end

    test "does not click the selector when matching text is hidden", %{conn: conn} do
      session =
        set_html(conn, """
        <button id="hidden-only-click-repro" onclick="this.dataset.clicked = 'true'">
          <span hidden>Delete</span>
        </button>
        """)

      assert_raise ArgumentError, ~r/Could not find element/, fn ->
        click(session, "#hidden-only-click-repro", "Delete", timeout: 100)
      end

      refute_has(session, "#hidden-only-click-repro[data-clicked=true]")
    end
  end

  describe "assert_download/2" do
    test "asserts a download triggered by clicking a link", %{conn: conn} do
      download_url = Application.fetch_env!(:phoenix_test, :base_url) <> "/pw/download"

      conn
      |> set_html(~s(<a href="#{download_url}">Download image</a>))
      |> click_link("Download image")
      |> assert_download(fn file ->
        assert file.name == "elixir.jpg"
        assert file.mime_type == "image/jpeg"
        assert file.content == File.read!("test/files/elixir.jpg")
      end)
    end
  end

  describe "evaluate/2" do
    test "evaluates JavaScript and returns the session", %{conn: conn} do
      conn
      |> set_html("<h1>Playwright</h1>")
      |> evaluate("document.title")
      |> assert_has("h1", text: "Playwright")
    end

    test "can modify the DOM", %{conn: conn} do
      conn
      |> set_html("<h1>Other</h1>")
      |> evaluate("document.querySelector('h1').textContent = 'Modified'")
      |> assert_has("h1", text: "Modified")
    end

    test "accepts function with arg", %{conn: conn} do
      conn
      |> set_html("<h1>Other</h1>")
      |> evaluate("selectors => selectors.forEach(s => document.querySelector(s).remove())",
        is_function: true,
        arg: ["h1"]
      )
      |> refute_has("h1")
    end

    test "raises on JavaScript error", %{conn: conn} do
      assert_raise ExUnit.AssertionError, fn ->
        conn
        |> set_html("<h1>Other</h1>")
        |> evaluate("nonExistentFunction()")
      end
    end

    test "passes result to callback when provided", %{conn: conn} do
      test_pid = self()

      conn
      |> set_html("<h1>Other</h1>")
      |> evaluate("document.querySelector('h1').textContent", fn title ->
        send(test_pid, {:title, title})
      end)
      |> assert_has("h1", text: "Other")

      assert_receive {:title, "Other"}
    end

    test "accepts opts and callback together", %{conn: conn} do
      test_pid = self()

      conn
      |> set_html("<h1>Other</h1>")
      |> evaluate("1 + 2", [timeout: 5000], fn result ->
        send(test_pid, {:result, result})
      end)

      assert_receive {:result, 3}
    end
  end

  describe "unwrap" do
    test "provides an escape hatch that gives access to the underlying frame", %{conn: conn} do
      conn
      |> set_html("""
      <a href="#other">Navigate</a>
      <h1 id="other">Other</h1>
      """)
      |> unwrap(fn %{frame_id: frame_id} ->
        selector = Selector.role("link", "Navigate", exact: true)
        {:ok, _} = PlaywrightEx.Frame.click(frame_id, selector: selector, timeout: timeout())
      end)
      |> assert_has("#other:target", text: "Other")
    end
  end

  describe "type/3" do
    test "fills in a single text field based on the label", %{conn: conn} do
      conn
      |> set_html("""
      <input
        id="text-input"
        oninput="document.querySelector('#changed-form-data').textContent = `text: ${this.value}`"
      />
      <div id="changed-form-data"></div>
      """)
      |> type("#text-input", "My text")
      |> assert_has("#changed-form-data", text: "text: My text")
    end
  end

  describe "press/3" do
    test "submits a form via Enter key", %{conn: conn} do
      conn
      |> set_html("""
      <form onsubmit="event.preventDefault(); document.querySelector('#submitted-form-data').textContent = `text: ${this.elements.text.value}`">
        <input id="text-input" name="text" />
      </form>
      <div id="submitted-form-data"></div>
      """)
      |> type("#text-input", "My text")
      |> press("#text-input", "Enter")
      |> assert_has("#submitted-form-data", text: "text: My text")
    end
  end

  describe "submit/1" do
    test "submits the form when the last interacted input is a select", %{conn: conn} do
      conn
      |> set_html("""
      <form onsubmit="event.preventDefault(); document.querySelector('#submitted-form-data').textContent = `select: ${this.elements.select.value}`">
        <label for="select-input">Select input</label>
        <select id="select-input" name="select">
          <option value="one">One</option>
          <option value="two">Two</option>
        </select>
      </form>
      <div id="submitted-form-data"></div>
      """)
      |> select("Select input", option: "Two")
      |> submit()
      |> assert_has("#submitted-form-data", text: "select: two")
    end
  end

  describe "drag/3" do
    @drag_html """
    <div id="drag-status">pending</div>
    <div id="drag-source" draggable="true" style="width: 100px; height: 30px">Drag this</div>
    <div
      id="drag-target"
      style="width: 100px; height: 30px"
      ondragover="event.preventDefault()"
      ondrop="document.getElementById('drag-status').textContent = 'dropped'"
    >
      Drop here
    </div>
    """

    test "triggers a javascript event handler", %{conn: conn} do
      conn
      |> set_html(@drag_html)
      |> refute_has("#drag-status", text: "dropped")
      |> drag(Selector.text("Drag this"), to: Selector.text("Drop here"))
      |> assert_has("#drag-status", text: "dropped")
    end

    test "passes custom options to playwright (effectively fails to drag, but without error)", %{conn: conn} do
      conn
      |> set_html(@drag_html)
      |> refute_has("#drag-status", text: "dropped")
      |> drag(Selector.text("Drag this"),
        to: Selector.text("Drop here"),
        playwright: [source_position: %{x: 0, y: 100}, force: true]
      )
      |> refute_has("#drag-status", text: "dropped")
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
      |> add_session_cookie(cookie, PhoenixTest.WebApp.Endpoint.session_options())
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
          |> set_html("<h1>Console log fixture</h1>")
          |> tap(&PlaywrightEx.Frame.evaluate(&1.frame_id, expression: "console.error('TESTME 42')", timeout: timeout()))
        end)

      assert log =~ "TESTME 42"
      refute log =~ "localhost"
    end
  end

  describe "new_session/2" do
    test "can create a second session in the same test", context do
      context.conn
      |> set_html("<h1>First session</h1>")
      |> assert_has("h1", text: "First session")

      config = PhoenixTest.Playwright.Config.validate!(%{})
      conn2 = PhoenixTest.Playwright.Case.new_session(config, context)

      conn2
      |> set_html("<h1>Second session</h1>")
      |> assert_has("h1", text: "Second session")
    end
  end

  describe "assert_path after live navigation" do
    test "live patch via click_link", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> click_link("Patch link")
      |> assert_path("/live/index", query_params: %{"details" => "true", "foo" => "bar"})
    end

    test "push patch via click_button", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> click_button("Button with push patch")
      |> assert_path("/live/index", query_params: %{"foo" => "bar"})
    end

    test "live navigate via click_link", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> click_link("Navigate link")
      |> assert_path("/live/page_2", query_params: %{"details" => "true", "foo" => "bar"})
    end

    test "push navigate via click_button", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> click_button("Button with push navigation")
      |> assert_path("/live/page_2", query_params: %{"foo" => "bar"})
    end
  end

  describe "phoenix_test locator semantics" do
    test "restores the outer scope after a nested within", %{conn: conn} do
      conn
      |> set_html("""
      <form id="email-form"></form>
      <form id="full-form">
        <fieldset><input id="email_choice" /></fieldset>
      </form>
      """)
      |> within("#full-form", fn outer ->
        outer
        |> within("fieldset", &assert_has(&1, "#email_choice"))
        |> refute_has("#email-form")
      end)
    end

    test "uses Playwright accessible-name precedence for labelled controls", %{conn: conn} do
      conn
      |> set_html("""
      <label for="accessible-search">HTML Search</label>
      <span id="accessible-search-name">ARIA Labelled Search</span>
      <input
        id="accessible-search"
        aria-label="ARIA Search"
        aria-labelledby="accessible-search-name"
        value="accessible-name"
      />
      """)
      |> assert_has("input", label: "ARIA Labelled Search", value: "accessible-name")
      |> refute_has("input", label: "ARIA Search")
      |> refute_has("input", label: "HTML Search")
    end
  end
end
