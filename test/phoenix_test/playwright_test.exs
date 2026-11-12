defmodule PhoenixTest.PlaywrightTest do
  @moduledoc """
  Tests for non-phoenix_test-standard behaviour.
  Standard behaviour should instead be covered by `./upstream` tests.
  """

  use PhoenixTest.Playwright.Case, async: true

  import ExUnit.CaptureLog, only: [capture_log: 1]
  import PhoenixTest.TestHelpers, only: [set_html: 2]

  alias PhoenixTest.Playwright.Case
  alias PhoenixTest.Playwright.Config
  alias PhoenixTest.Playwright.JsLogger
  alias PhoenixTest.Playwright.Selector
  alias PlaywrightEx.ConsoleMessage
  alias PlaywrightEx.WebError

  defmodule ForwardingJsLogger do
    @moduledoc false
    @behaviour JsLogger

    @impl true
    def log(level, text, message), do: send(PhoenixTest.PlaywrightTest, {:js_log, level, text, message})
  end

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
      assert File.exists?(PlaywrightEx.Test.output_path(name))
    end

    test "infers the image type from the file extension", %{conn: conn} do
      name = "inferred_#{System.unique_integer([:positive])}.jpg"
      screenshot(conn, name)
      assert <<0xFF, 0xD8, 0xFF, _rest::binary>> = File.read!(PlaywrightEx.Test.output_path(name))
    end

    test "ignores omit_background for a JPEG", %{conn: conn} do
      plain = "plain_#{System.unique_integer([:positive])}.jpg"
      omitted = "omitted_#{System.unique_integer([:positive])}.jpg"

      conn
      |> screenshot(plain, omit_background: false)
      |> screenshot(omitted, omit_background: true)

      assert File.read!(PlaywrightEx.Test.output_path(omitted)) == File.read!(PlaywrightEx.Test.output_path(plain))
    end

    test "full page screenshots are larger in file size than non-full-page", %{conn: conn} do
      full_page_name = "full_page_#{:erlang.system_time(:second)}.png"
      viewport_name = "viewport_#{:erlang.system_time(:second)}.png"

      conn
      |> screenshot(full_page_name, full_page: true)
      |> screenshot(viewport_name, full_page: false)

      assert {:ok, %File.Stat{size: full_page_size}} = File.stat(PlaywrightEx.Test.output_path(full_page_name))
      assert {:ok, %File.Stat{size: viewport_size}} = File.stat(PlaywrightEx.Test.output_path(viewport_name))

      assert full_page_size > viewport_size
    end
  end

  describe "assert_screenshot/3" do
    setup %{conn: conn} do
      # A dir of new baselines per test, see `config :playwright_ex, :test` in config/test.exs.
      dir = "tmp-#{System.unique_integer([:positive])}"
      on_exit(fn -> File.rm_rf!(Path.join("test/snapshots", dir)) end)
      [conn: set_html(conn, @screenshot_html), dir: dir]
    end

    test "captures baseline on first run and writes file", %{conn: conn, dir: dir} do
      assert_screenshot(conn, "#{dir}/capture.png")
      assert File.exists?("test/snapshots/#{dir}/capture.png")
    end

    test "passes silently when screenshot matches baseline", %{conn: conn} do
      # Add max_diff_pixel_ratio to account for different font locally vs CI
      assert_screenshot(conn, "baseline.png", max_diff_pixel_ratio: 0.01)
    end

    test "raises when screenshot does not match baseline", %{conn: conn} do
      assert_raise ExUnit.AssertionError,
                   ~r"\d+ pixels \(ratio \d+(?:\.\d+)? of all image pixels\) are different\.",
                   fn ->
                     conn
                     |> set_html("<h1>Different screenshot</h1>")
                     |> assert_screenshot("baseline.png")
                   end

      assert [_diff] = output_files("baseline-diff.png")
      refute File.exists?("test/snapshots/baseline-diff.png")
    end

    test "raises on invalid clip option", %{conn: conn, dir: dir} do
      assert_raise ExUnit.AssertionError,
                   ~r"Expected options.clip.width to be greater than 0.",
                   fn -> assert_screenshot(conn, "#{dir}/clip.png", clip: %{x: 0, y: 0, width: 0, height: 100}) end
    end

    test "accepts enum options as strings and atoms", %{conn: conn, dir: dir} do
      assert_screenshot(conn, "#{dir}/strings.png", animations: "disabled", caret: "hide", scale: "css")
      assert_screenshot(conn, "#{dir}/atoms.png", animations: :allow, caret: :initial, scale: :device)
    end

    test "creates subdirectory for nested name", %{conn: conn, dir: dir} do
      assert_screenshot(conn, "#{dir}/subdir/nested.png")
      assert File.exists?("test/snapshots/#{dir}/subdir/nested.png")
    end

    test "scopes screenshot to element when selector opt is given", %{conn: conn, dir: dir} do
      assert_screenshot(conn, "#{dir}/selector.png", selector: "h1")

      # Change the color of a sibling element — full-page screenshot would differ, but scoped to h1 it still matches
      conn
      |> evaluate("document.querySelector('#sibling').style.backgroundColor = 'blue'")
      |> assert_screenshot("#{dir}/selector.png", selector: "h1")
    end

    test "masks elements so changes within them don't cause mismatch", %{conn: conn, dir: dir} do
      assert_screenshot(conn, "#{dir}/mask.png", mask: ["h1"])

      # Change the h1 text — masked element differs, but screenshot still matches
      conn
      |> evaluate("document.querySelector('h1').textContent = 'changed'")
      |> assert_screenshot("#{dir}/mask.png", mask: ["h1"])
    end

    test "leaves only the baseline next to a new snapshot", %{conn: conn, dir: dir} do
      assert_screenshot(conn, "#{dir}/only.png")

      assert File.ls!("test/snapshots/#{dir}") == ["only.png"]
    end

    test "keeps other files next to a matching snapshot", %{conn: conn, dir: dir} do
      assert_screenshot(conn, "#{dir}/kept.png")
      siblings = Enum.map(~w(kept-previous.png kept-actual.png), &Path.join("test/snapshots/#{dir}", &1))
      Enum.each(siblings, &File.write!(&1, "unrelated"))

      assert_screenshot(conn, "#{dir}/kept.png")

      assert Enum.map(siblings, &File.read!/1) == ["unrelated", "unrelated"]
    end

    @tag :tmp_dir
    test "applies the :style_path stylesheet", %{conn: conn, dir: dir, tmp_dir: tmp_dir} do
      style_path = Path.join(tmp_dir, "hide.css")
      File.write!(style_path, "#sibling { visibility: hidden; }")
      assert_screenshot(conn, "#{dir}/styled.png", style_path: style_path)

      # The hidden sibling changes, so this only matches because the stylesheet is applied.
      conn
      |> evaluate("document.querySelector('#sibling').style.backgroundColor = 'blue'")
      |> assert_screenshot("#{dir}/styled.png", style_path: style_path)
    end

    test "rejects invalid option values", %{conn: conn, dir: dir} do
      for opt <- [animations: false, caret: "bogus", full_page: "yes", threshold: "0.1", snapshot_dir: "test"] do
        assert_raise NimbleOptions.ValidationError, fn ->
          assert_screenshot(conn, "#{dir}/invalid.png", [opt])
        end
      end
    end

    test "raises without writing diff when comparison times out", %{conn: conn} do
      assert_raise ExUnit.AssertionError, ~r"Timeout 1ms exceeded.", fn ->
        conn
        |> set_html("<h1>Different screenshot</h1>")
        |> assert_screenshot("baseline.png", timeout: 1)
      end

      assert output_files("baseline-diff.png") == []
    end
  end

  defp output_files(name), do: Path.wildcard(Path.join(PlaywrightEx.Test.info().output_dir, "**/#{name}"))

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

    @tag accept_dialogs: false
    test "with_dialog/3 nests and restores the outer listener", %{conn: conn} do
      conn
      |> set_html("""
      <button onclick="document.getElementById('result').textContent = confirm('Sure?')">Ask</button>
      <p id="result"></p>
      """)
      |> with_dialog(
        fn _ -> :accept end,
        fn outer ->
          outer = outer |> click_button("Ask") |> assert_has("#result", text: "true", exact: true)

          nested =
            with_dialog(
              outer,
              fn _ -> :dismiss end,
              &(&1 |> click_button("Ask") |> assert_has("#result", text: "false", exact: true))
            )

          assert nested.dialog_listener == outer.dialog_listener
          nested |> click_button("Ask") |> assert_has("#result", text: "true", exact: true)
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
    test "raises the underlying error for an invalid selector", %{conn: conn} do
      session = set_html(conn, "<h1>Playwright</h1>")

      assert_raise PlaywrightEx.ExpectError, fn -> assert_has(session, "h1[") end
      assert_raise PlaywrightEx.ExpectError, fn -> refute_has(session, "h1[") end
    end

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

    test "asserts repeated downloads in order", %{conn: conn} do
      conn
      |> set_html(download_links(~w(first.txt second.txt)))
      |> click_link("first.txt")
      |> click_link("second.txt")
      |> assert_download("first.txt")
      |> assert_download("second.txt")
    end

    test "keeps downloads of a second session apart", context do
      config = Config.validate!(%{})
      conn2 = Case.new_session(config, context)

      conn1 =
        context.conn
        |> set_html(download_links(~w(first.txt)))
        |> click_link("first.txt")

      conn2
      |> set_html(download_links(~w(second.txt)))
      |> click_link("second.txt")
      |> assert_download("second.txt")

      assert_download(conn1, "first.txt")
    end

    defp download_links(names) do
      Enum.map_join(names, &~s(<a href="data:text/plain,#{&1}" download="#{&1}">#{&1}</a>))
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
      |> evaluate("selectors => selectors.forEach(s => document.querySelector(s).remove())", arg: ["h1"])
      |> refute_has("h1")
    end

    test "rejects the removed is_function option", %{conn: conn} do
      assert_raise NimbleOptions.ValidationError, ~r/unknown.*:is_function/, fn ->
        evaluate(conn, "1 + 2", is_function: true)
      end
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
      |> evaluate("({ a: null, b: [null] })", fn result -> assert result == %{"a" => :null, "b" => [:null]} end)
      |> evaluate("null", fn result -> assert result == :null end)
      |> evaluate("undefined", fn result -> assert result == nil end)
      |> evaluate("x => x + 2", [arg: 1], fn result ->
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
      |> unwrap(fn %{page: page} ->
        selector = Selector.role("link", "Navigate", exact: true)
        page |> PlaywrightEx.Page.locator(selector) |> PlaywrightEx.Locator.click!()
      end)
      |> assert_has("#other:target", text: "Other")
    end
  end

  describe "type/3" do
    test "acts on the first match", %{conn: conn} do
      conn
      |> set_html(~s(<input id="first" /><input id="second" />))
      |> type("input", "My text")
      |> assert_has("#first", value: "My text")
      |> refute_has("#second", value: "My text")
    end

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
    test "acts on the first match", %{conn: conn} do
      conn
      |> set_html(~s(<input id="first" /><input id="second" />))
      |> press("input", "a")
      |> assert_has("#first", value: "a")
      |> refute_has("#second", value: "a")
    end

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

    test "raises when the last interacted input is not associated with a form", %{conn: conn} do
      conn =
        conn
        |> set_html(~s(<label for="text-input">Text</label><input id="text-input" />))
        |> fill_in("Text", with: "value")

      assert_raise ExUnit.AssertionError, ~r/Could not submit form.*not associated with a form/s, fn ->
        submit(conn)
      end
    end

    test "raises when the last interacted input no longer exists", %{conn: conn} do
      conn =
        conn
        |> set_html(~s(<form><label for="text-input">Text</label><input id="text-input" /></form>))
        |> fill_in("Text", with: "value")
        |> evaluate("document.querySelector('form').remove()")

      assert_raise ArgumentError, ~r/Could not find element/, fn -> submit(conn) end
    end

    test "raises when the last interacted input became ambiguous", %{conn: conn} do
      conn =
        conn
        |> set_html(~s(<form><label>Text <input /></label></form>))
        |> fill_in("Text", with: "value")
        |> evaluate("document.querySelector('form').insertAdjacentHTML('beforeend', '<label>Text <input /></label>')")

      assert_raise ArgumentError, ~r/more than one element/, fn -> submit(conn) end
    end
  end

  describe "current_path" do
    test "returns the path and query without the fragment", %{conn: conn} do
      assert conn |> visit("/page/index?foo=bar&baz=a%20b#section") |> PhoenixTest.Driver.current_path() ==
               "/page/index?foo=bar&baz=a%20b"
    end

    test "omits an empty query", %{conn: conn} do
      assert conn |> visit("/page/index?#section") |> PhoenixTest.Driver.current_path() == "/page/index"
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

  describe "text with quotes and backslashes" do
    @name ~S(Say "hi" \o/)

    test "is matched by assert_has, click_link, click_button and fill_in", %{conn: conn} do
      conn
      |> set_html("""
      <p id="text">#{@name}</p>
      <a href="#">#{@name}</a>
      <button onclick="document.querySelector('#out').textContent = 'clicked'">#{@name}</button>
      <label for="field">#{@name}</label><input id="field" />
      <p id="out"></p>
      """)
      |> assert_has("#text", text: @name)
      |> click_link(@name)
      |> click_button(@name)
      |> assert_has("#out", text: "clicked")
      |> fill_in(@name, with: "filled")
      |> evaluate("document.querySelector('#field').value", fn value -> assert value == "filled" end)
    end

    test "is matched by the value option of assert_has and refute_has", %{conn: conn} do
      value = ~S(it's \o/ >> "x")

      conn
      |> set_html(~s(<input id="field" />))
      |> evaluate("value => { document.querySelector('#field').value = value }", arg: value)
      |> assert_has("#field", value: value)
      |> refute_has("#field", value: value <> "x")
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
          |> tap(&PlaywrightEx.Page.evaluate(&1.page, "console.error('TESTME 42')"))
        end)

      assert log =~ "TESTME 42"
      refute log =~ "localhost"
    end

    @tag :capture_log
    test "passes PlaywrightEx objects to a custom logger", %{conn: conn} do
      Process.register(self(), PhoenixTest.PlaywrightTest)
      JsLogger.attach(conn.context, ForwardingJsLogger)

      conn
      |> set_html("<h1>Console log fixture</h1>")
      |> tap(&PlaywrightEx.Page.evaluate(&1.page, "console.error('TESTME 42')"))
      |> tap(&PlaywrightEx.Page.evaluate(&1.page, "setTimeout(() => { throw new Error('TESTME 43') })"))

      assert_receive {:js_log, :error, "TESTME 42", %ConsoleMessage{}}, 5_000
      assert_receive {:js_log, :error, "TESTME 43", %WebError{}}, 5_000
    end
  end

  describe "new_session/2" do
    test "can create a second session in the same test", context do
      context.conn
      |> set_html("<h1>First session</h1>")
      |> assert_has("h1", text: "First session")

      config = Config.validate!(%{})
      conn2 = Case.new_session(config, context)

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

    test "honors exact matching for assertion labels", %{conn: conn} do
      conn =
        set_html(conn, """
        <label for="name">Account name <span>*</span></label>
        <input id="name" value="Frodo" />
        """)

      assert_has(conn, "input", label: "Account name", value: "Frodo", exact: false)
      refute_has(conn, "input", label: "Account name", value: "Frodo", exact: true)

      assert_raise ExUnit.AssertionError, fn ->
        refute_has(conn, "input", label: "Account name", value: "Frodo", exact: false)
      end
    end
  end
end
