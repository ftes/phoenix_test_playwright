defmodule PhoenixTest.PlaywrightTest do
  use PhoenixTest.Playwright.Case, async: true

  import ExUnit.CaptureLog, only: [capture_log: 1]

  alias ExUnit.AssertionError
  alias PhoenixTest.Playwright

  describe "visit/2" do
    test "navigates to given LiveView page", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> assert_has("h1", text: "LiveView main page")
    end

    test "user can visit different pages sequentially", %{conn: conn} do
      conn
      |> visit("/live/page_2")
      |> visit("/live/index")
      |> assert_has("h1", text: "LiveView main page")
    end
  end

  describe "render_html/2" do
    test "doesn't fail", %{conn: conn} do
      assert conn
             |> visit("/live/index")
             |> Playwright.render_html() =~ "<body"
    end
  end

  describe "screenshot/3" do
    test "takes a screenshot of the current page as a PNG", %{conn: conn} do
      name = "png_#{:erlang.system_time(:second)}.png"

      conn
      |> visit("/live/index")
      |> assert_has("h1", text: "LiveView main page")
      |> screenshot(name, full_page: false, omit_background: true)

      assert File.exists?("screenshots/#{name}")
    end

    test "takes a screenshot of the current page as a JPEG", %{conn: conn} do
      name = "jpg_#{:erlang.system_time(:second)}.jpg"

      conn
      |> visit("/live/index")
      |> assert_has("h1", text: "LiveView main page")
      |> screenshot(name)

      assert File.exists?("screenshots/#{name}")
    end

    test "full page screenshots are larger in file size than non-full-page", %{conn: conn} do
      full_page_name = "full_page_#{:erlang.system_time(:second)}.png"
      viewport_name = "viewport_#{:erlang.system_time(:second)}.png"

      conn
      |> visit("/live/index")
      |> assert_has("h1", text: "LiveView main page")
      |> screenshot(full_page_name, full_page: true)
      |> screenshot(viewport_name, full_page: false)

      assert {:ok, %File.Stat{size: full_page_size}} = File.stat("screenshots/#{full_page_name}")
      assert {:ok, %File.Stat{size: viewport_size}} = File.stat("screenshots/#{viewport_name}")

      assert full_page_size > viewport_size
    end
  end

  describe "click_link/2" do
    test "follows 'navigate' links", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> click_link("Navigate link")
      |> assert_has("h1", text: "LiveView page 2")
    end

    test "accepts click_link with selector", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> click_link("a", "Navigate link")
      |> assert_has("h1", text: "LiveView page 2")
    end

    test "raises error when there are multiple links with same text", %{conn: conn} do
      assert_raise AssertionError, ~r/Found more than one/, fn ->
        conn
        |> visit("/live/index")
        |> click_link("Multiple links")
      end
    end

    test "raises an error when link element can't be found with given text", %{conn: conn} do
      assert_raise AssertionError, ~r/Could not find element/, fn ->
        conn
        |> visit("/live/index")
        |> click_link("No link")
      end
    end
  end

  describe "click_button/2" do
    test "handles a `phx-click` button", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> click_button("Show tab")
      |> assert_has("#tab", text: "Tab title")
    end

    test "raises an error when there are no buttons on page", %{conn: conn} do
      assert_raise AssertionError, ~r/Could not find/, fn ->
        conn
        |> visit("/live/page_2")
        |> click_button("Show tab")
      end
    end
  end

  describe "within/3" do
    test "scopes assertions within selector", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> assert_has("button", text: "Reset")
      |> within("#email-form", fn conn ->
        refute_has(conn, "button", text: "Reset")
      end)
    end

    test "nests selector when multiple withins", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> assert_has("button", text: "Reset")
      |> within("#full-form", fn conn ->
        within(conn, "#contact", fn conn ->
          assert_has(conn, "label", text: "Email choice")
        end)
      end)
    end

    test "scopes further form actions within a selector", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> within("#email-form", fn conn ->
        fill_in(conn, "Email", with: "someone@example.com")
      end)
      |> assert_has("#form-data", text: "email: someone@example.com")
    end

    test "raises when data is not in scoped HTML", %{conn: conn} do
      assert_raise AssertionError, ~r/Could not find element/, fn ->
        conn
        |> visit("/live/index")
        |> within("#email-form", fn conn ->
          fill_in(conn, "User Name", with: "Aragorn")
        end)
      end
    end
  end

  describe "browser dialog handling: accept_dialogs config and with_dialog/3" do
    test "accepts dialog by default", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> click_link("Confirm to navigate")
      |> assert_path("/live/page_2")
    end

    @tag accept_dialogs: false
    test "override config via tag: dismisses dialog and fails click_link", %{conn: conn} do
      assert_raise AssertionError, fn ->
        conn
        |> visit("/live/index")
        |> click_link("Confirm to navigate")
      end
    end

    @tag accept_dialogs: false
    test "with_dialog/3 accepts dialog conditionally", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> with_dialog(
        fn %{message: "Are you sure?"} -> :accept end,
        fn conn ->
          conn
          |> click_link("Confirm to navigate")
          |> assert_path("/live/page_2")
        end
      )
    end
  end

  describe "fill_in/4" do
    test "fills in a single text field based on the label", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> within("#email-form", fn conn ->
        fill_in(conn, "Email", with: "someone@example.com")
      end)
      |> assert_has("#form-data", text: "email: someone@example.com")
    end

    test "can fill input with `nil` to override existing value", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> within("#pre-rendered-data-form", fn conn ->
        fill_in(conn, "Pre Rendered Input", with: nil)
      end)
      |> assert_has("#form-data", text: "input's value is empty")
    end

    test "can fill-in textareas", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> fill_in("Notes", with: "Dunedain. Heir to the throne. King of Arnor and Gondor")
      |> click_button("Save Full Form")
      |> assert_has("#form-data",
        text: "notes: Dunedain. Heir to the throne. King of Arnor and Gondor"
      )
    end

    test "can target a label with exact: false", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> within("#complex-labels", fn conn ->
        fill_in(conn, "Name", with: "Frodo", exact: false)
      end)
      |> assert_has("#form-data", text: "name: Frodo")
    end

    test "can target input with selector if multiple labels have same text", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> within("#same-labels", fn conn ->
        fill_in(conn, "#book-characters", "Character", with: "Frodo")
      end)
      |> assert_has("#form-data", text: "book-characters: Frodo")
    end

    test "triggers phx-change event if phx-debounce=blur", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> fill_in("Debounce blur", with: "triggers")
      |> assert_has("#form-data", text: "debounce-blur: triggers")
    end

    test "raises an error when element can't be found with label", %{conn: conn} do
      assert_raise AssertionError, ~r/Could not find element/, fn ->
        conn
        |> visit("/live/index")
        |> fill_in("Non-existent Email Label", with: "some@example.com")
      end
    end

    test "raises an error when label is found but no corresponding input is found", %{conn: conn} do
      assert_raise AssertionError, ~r/Could not find element/, fn ->
        conn
        |> visit("/live/index")
        |> fill_in("Email (no input)", with: "some@example.com")
      end
    end
  end

  describe "select/3" do
    test "selects given option for a label", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> select("Race", option: "Elf")
      |> assert_has("#full-form option[value='elf']")
    end

    test "allows selecting option if a similar option exists", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> select("Race", option: "Orc")
      |> assert_has("#full-form option[value='orc']")
    end

    @tag skip: "failing to select any option"
    test "works for multiple select", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> select("Race 2", option: ["Elf", "Dwarf"])
      |> click_button("Save Full Form")
      |> assert_has("#form-data", text: "[elf, dwarf]")
    end

    test "can target a label with exact: false", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> within("#complex-labels", fn conn ->
        select(conn, "Choose a pet:", option: "Cat", exact: false)
      end)
      |> assert_has("#form-data", text: "pet: cat")
    end

    @tag skip: true, reason: :not_implemented, not_implemented: :exact_option
    test "can target an option's text with exact_option: false", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> within("#full-form", fn conn ->
        select(conn, "Race", option: "Dwa", exact_option: false)
      end)
      |> submit()
      |> assert_has("#form-data", text: "race: dwarf")
    end

    test "can target option with selector if multiple labels have same text", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> within("#same-labels", fn conn ->
        select(conn, "#select-favorite-character", "Character", option: "Frodo")
      end)
      |> assert_has("#form-data", text: "favorite-character: Frodo")
    end
  end

  describe "check/3" do
    test "checks a checkbox", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> check("Admin")
      |> click_button("Save Full Form")
      |> assert_has("#form-data", text: "admin: on")
    end

    test "can check an unchecked checkbox", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> uncheck("Admin")
      |> check("Admin")
      |> click_button("Save Full Form")
      |> assert_has("#form-data", text: "admin: on")
    end

    test "handle checkbox name with '?'", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> check("Subscribe")
      |> click_button("Save Full Form")
      |> assert_has("#form-data", text: "subscribe?: on")
    end

    test "can target a label with exact: false", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> within("#complex-labels", fn conn ->
        check(conn, "Human", exact: false)
      end)
      |> assert_has("#form-data", text: "human: yes")
    end

    test "can specify input selector when multiple checkboxes have same label", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> within("#same-labels", fn conn ->
        check(conn, "#like-elixir", "Yes")
      end)
      |> assert_has("#form-data", text: "like-elixir: yes")
    end
  end

  describe "uncheck/3" do
    test "can uncheck a previous check/2 in the test", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> check("Admin")
      |> uncheck("Admin")
      |> click_button("Save Full Form")
      |> assert_has("#form-data", text: "admin: off")
    end

    test "can target a label with exact: false", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> within("#complex-labels", fn conn ->
        conn
        |> check("Human", exact: false)
        |> uncheck("Human", exact: false)
      end)
      |> assert_has("#form-data", text: "human: no")
    end

    test "can specify input selector when multiple checkboxes have same label", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> within("#same-labels", fn conn ->
        conn
        |> check("#like-elixir", "Yes")
        |> uncheck("#like-elixir", "Yes")
      end)
      |> assert_has("#form-data", text: "like-elixir: no")
      |> refute_has("#form-data", text: "like-elixir: yes")
    end
  end

  describe "choose/3" do
    test "chooses an option in radio button", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> choose("Email Choice")
      |> click_button("Save Full Form")
      |> assert_has("#form-data", text: "contact: email")
    end

    test "can target a label with exact: false", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> within("#complex-labels", fn conn ->
        choose(conn, "Book", exact: false)
      end)
      |> assert_has("#form-data", text: "book-or-movie: book")
    end

    test "can specify input selector when multiple options have same label in same form", %{
      conn: conn
    } do
      conn
      |> visit("/live/index")
      |> within("#same-labels", fn conn ->
        choose(conn, "#elixir-yes", "Yes")
      end)
      |> assert_has("#form-data", text: "elixir-yes: yes")
    end
  end

  describe "upload/4" do
    test "uploads an image", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> within("#full-form", fn conn ->
        conn
        |> upload("Avatar", "test/files/elixir.jpg")
        |> click_button("Save Full Form")
      end)
      |> assert_has("#form-data", text: "avatar: elixir.jpg")
    end

    test "can target a label with exact: false", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> within("#complex-labels", fn conn ->
        conn
        |> upload("Avatar", "test/files/elixir.jpg", exact: false)
        |> click_button("Save")
      end)
      |> assert_has("#form-data", text: "avatar: elixir.jpg")
    end

    test "can specify input selector when multiple inputs have same label", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> within("#same-labels", fn conn ->
        conn
        |> upload("[name='main_avatar']", "Avatar", "test/files/elixir.jpg")
        |> click_button("Submit Form")
      end)
      |> assert_has("#form-data", text: "main_avatar: elixir.jpg")
    end
  end

  describe "submit/1" do
    test "submits a pre-filled form via phx-submit", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> within("#email-form", fn conn ->
        fill_in(conn, "Email", with: "some@example.com")
      end)
      |> submit()
      |> assert_has("#form-data", text: "email: some@example.com")
    end

    test "can submit form without button", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> fill_in("Country of Origin", with: "Arnor")
      |> submit()
      |> assert_has("#form-data", text: "country: Arnor")
    end
  end

  describe "open_browser" do
    setup do
      open_fun = fn path ->
        assert content = File.read!(path)

        assert content =~
                 ~r[<link rel="stylesheet" href="file:.*phoenix_test_playwright\/priv\/static\/assets\/app\.css"\/>]

        assert content =~ ~s(<link rel="stylesheet" href="//example.com/cool-styles.css"/>)
        assert content =~ "body { font-size: 12px; }"

        assert content =~ ~r/<h1.*Main page/

        refute content =~ "<script>"
        refute content =~ "console.log(\"Hey, I'm some JavaScript!\")"
        refute content =~ "</script>"

        path
      end

      %{open_fun: open_fun}
    end

    test "opens the browser ", %{conn: conn, open_fun: open_fun} do
      conn
      |> visit("/page/index")
      |> open_browser(open_fun)
      |> assert_has("h1", text: "Main page")
    end
  end

  describe "unwrap" do
    test "provides an escape hatch that gives access to the underlying frame", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> unwrap(fn %{frame_id: frame_id} ->
        selector = Playwright.Selector.role("link", "Navigate link", exact: true)
        {:ok, _} = Playwright.Frame.click(frame_id, selector)
      end)
      |> assert_has("h1", text: "LiveView page 2")
    end
  end

  describe "shared form helpers behavior" do
    test "triggers phx-change validations", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> within("#email-form", fn conn ->
        conn
        |> fill_in("Email", with: "email")
        |> fill_in("Email", with: nil)
      end)
      |> assert_has("#form-errors", text: "Errors present")
    end
  end

  describe "assert_has/2" do
    test "succeeds if single element is found with CSS selector", %{conn: conn} do
      conn
      |> visit("/page/index")
      |> assert_has("[data-role='title']")
    end

    test "raises an error if the element cannot be found at all", %{conn: conn} do
      assert_raise AssertionError, ~r/Could not find element/, fn ->
        conn
        |> visit("/page/index")
        |> assert_has("#nonexistent-id")
      end
    end

    test "succeeds if more than one element matches selector", %{conn: conn} do
      conn
      |> visit("/page/index")
      |> assert_has("li")
    end
  end

  describe "assert_has/3" do
    test "title text match", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> assert_has("title", text: "PhoenixTest is the best!")
    end

    test "succeeds if single element is found with CSS selector and text", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> assert_has("h1", text: "LiveView main page")
      |> assert_has("#title", text: "LiveView main page")
      |> assert_has(".title", text: "LiveView main page")
      |> assert_has("[data-role='title']", text: "LiveView main page")
    end

    test "succeeds if more than one element matches selector but text narrows it down", %{
      conn: conn
    } do
      conn
      |> visit("/page/index")
      |> assert_has("li", text: "Aragorn")
    end

    test "succeeds if more than one element matches selector and text", %{conn: conn} do
      conn
      |> visit("/page/index")
      |> assert_has(".multiple_links", text: "Multiple links")
    end

    test "succeeds if text difference is only a matter of truncation", %{conn: conn} do
      conn
      |> visit("/page/index")
      |> assert_has(".has_extra_space", text: "Has extra space")
    end

    test "raises an error if the element cannot be found at all", %{conn: conn} do
      assert_raise AssertionError, ~r/Could not find element/, fn ->
        conn
        |> visit("/page/index")
        |> assert_has("#nonexistent-id", text: "Main page")
      end
    end

    test "accepts a `count` option", %{conn: conn} do
      conn
      |> visit("/page/index")
      |> assert_has(".multiple_links", count: 2)
      |> assert_has(".multiple_links", text: "Multiple links", count: 2)
      |> assert_has("h1", count: 1)
      |> assert_has("h1", text: "Main page", count: 1)
    end

    test "raises an error if count is more than expected count", %{conn: conn} do
      conn = visit(conn, "/page/index")

      assert_raise AssertionError, ~r/Could not find element/, fn ->
        assert_has(conn, ".multiple_links", count: 1)
      end
    end

    test "raises an error if count is less than expected count", %{conn: conn} do
      conn = visit(conn, "/page/index")

      assert_raise AssertionError, ~r/Could not find element/, fn ->
        assert_has(conn, "h1", count: 2)
      end
    end

    test "accepts an `exact` option to match text exactly", %{conn: conn} do
      conn
      |> visit("/page/index")
      |> assert_has("h1", text: "Main", exact: false)
      |> assert_has("h1", text: "Main page", exact: true)
    end

    test "raises if `exact` text doesn't match", %{conn: conn} do
      assert_raise AssertionError, ~r/Could not find element/, fn ->
        conn
        |> visit("/page/index")
        |> assert_has("h1", text: "Main", exact: true)
      end
    end

    test "raises if it cannot find element at `at` position", %{conn: conn} do
      assert_raise AssertionError, ~r/Could not find element/, fn ->
        conn
        |> visit("/page/index")
        |> assert_has("#multiple-items li", at: 2, text: "Aragorn")
      end
    end
  end

  describe "refute_has/2" do
    test "title without text", %{conn: conn} do
      conn
      |> visit("/live/index_no_layout")
      |> refute_has("title")
    end

    test "succeeds if no element is found with CSS selector", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> refute_has("#some-invalid-id")
      |> refute_has("[data-role='invalid-role']")
    end

    test "accepts a `count` option", %{conn: conn} do
      conn
      |> visit("/page/index")
      |> refute_has("h1", count: 2)
      |> refute_has("h1", text: "Main page", count: 2)
      |> refute_has(".multiple_links", count: 1)
      |> refute_has(".multiple_links", text: "Multiple links", count: 1)
    end

    test "raises if element is found", %{conn: conn} do
      assert_raise AssertionError, ~r/Found element/, fn ->
        conn
        |> visit("/page/index")
        |> refute_has("h1")
      end
    end

    test "raises an error if multiple elements are found", %{conn: conn} do
      assert_raise AssertionError, ~r/Found element/, fn ->
        conn
        |> visit("/page/index")
        |> refute_has(".multiple_links")
      end
    end

    test "raises if there is one element and count is 1", %{conn: conn} do
      assert_raise AssertionError, ~r/Found element/, fn ->
        conn
        |> visit("/page/index")
        |> refute_has("h1", count: 1)
      end
    end

    test "raises if there are the same number of elements as refuted", %{conn: conn} do
      assert_raise AssertionError, ~r/Found element/, fn ->
        conn
        |> visit("/page/index")
        |> refute_has(".multiple_links", count: 2)
      end
    end

    test "retries if element initially visible", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> click_button("Button with push navigation")
      |> refute_has("h1", text: "main page")
    end
  end

  describe "refute_has/3" do
    test "succeeds if no element is found with CSS selector and text", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> refute_has("h1", text: "Not main page")
      |> refute_has("h2", text: "Main page")
      |> refute_has("#incorrect-id", text: "Main page")
      |> refute_has("#title", text: "Not main page")
    end

    test "raises an error if one element is found", %{conn: conn} do
      assert_raise AssertionError, ~r/Found element/, fn ->
        conn
        |> visit("/page/index")
        |> refute_has("#title", text: "Main page")
      end
    end

    test "raises an error if multiple elements are found", %{conn: conn} do
      assert_raise AssertionError, ~r/Found element/, fn ->
        conn
        |> visit("/page/index")
        |> refute_has(".multiple_links", text: "Multiple links")
      end
    end

    test "accepts an `exact` option to match text exactly", %{conn: conn} do
      conn
      |> visit("/page/index")
      |> refute_has("h1", text: "Main", exact: true)
    end

    test "raises if `exact` text makes refutation false", %{conn: conn} do
      assert_raise AssertionError, ~r/Found element/, fn ->
        conn
        |> visit("/page/index")
        |> refute_has("h1", text: "Main", exact: false)
      end
    end

    test "accepts an `at` option (without text) to refute on a specific element", %{conn: conn} do
      conn
      |> visit("/page/index")
      |> refute_has("#single-list-item li", at: 2)
    end

    test "accepts an `at` option with text to refute on a specific element", %{conn: conn} do
      conn
      |> visit("/page/index")
      |> refute_has("#multiple-items li", at: 2, text: "Aragorn")
    end
  end

  describe "assert_path" do
    test "it is set on visit", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> assert_path("/live/index")
    end

    test "it is set on visit with query string", %{conn: conn} do
      conn
      |> visit("/live/index?foo=bar")
      |> assert_path("/live/index", query_params: %{foo: "bar"})
    end

    test "it is updated on href navigation", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> click_link("Navigate to non-liveview")
      |> assert_path("/page/index", query_params: %{details: "true", foo: "bar"})
    end

    test "it is updated on push patch", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> click_button("Button with push patch")
      |> assert_path("/live/index", query_params: %{foo: "bar"})
    end

    test "asserts query params are the same", %{conn: conn} do
      conn
      |> visit("/page/index?hello=world")
      |> assert_path("/page/index", query_params: %{"hello" => "world"})
    end
  end

  describe "refute_path" do
    test "refutes query params are the same", %{conn: conn} do
      conn
      |> visit("/page/index?hello=world")
      |> refute_path("/page/index", query_params: %{"hello" => "not-world"})
    end
  end

  describe "type/3" do
    test "fills in a single text field based on the label", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> type("#email", "someone@example.com")
      |> assert_has("#form-data", text: "email: someone@example.com")
    end
  end

  describe "press/3" do
    test "submits a form via Enter key", %{conn: conn} do
      conn
      |> visit("/live/index")
      |> type("#redirect-form-name", "name")
      |> press("#redirect-form-name", "Enter")
      |> assert_path("/live/page_2")
    end
  end

  describe "add_cookies/2" do
    test "sets a plain cookie", %{conn: conn} do
      conn
      |> add_cookies([[name: "name", value: "42"]])
      |> visit("/page/cookies")
      |> assert_has("#form-data", text: "name: 42")
    end

    test "sets an encrypted cookie", %{conn: conn} do
      conn
      |> add_cookies([[name: "name", value: "42", encrypt: true]])
      |> visit("/page/cookies?encrypted[]=")
      |> assert_has("#form-data", text: "name:")
      |> refute_has("#form-data", text: "name: 42")

      conn
      |> add_cookies([[name: "name", value: "42", encrypt: true]])
      |> visit("/page/cookies?encrypted[]=name")
      |> assert_has("#form-data", text: "name: 42")
    end

    test "sets a signed cookie", %{conn: conn} do
      conn
      |> add_cookies([[name: "name", value: "42", sign: true]])
      |> visit("/page/cookies?signed[]=")
      |> assert_has("#form-data", text: "name:")
      |> refute_has("#form-data", text: "name: 42")

      conn
      |> add_cookies([[name: "name", value: "42", sign: true]])
      |> visit("/page/cookies?signed[]=name")
      |> assert_has("#form-data", text: "name: 42")
    end
  end

  describe "add_session_cookie/3" do
    test "puts a signed, encrypted cookie on the Conn", %{conn: conn} do
      cookie = [value: %{secret: "monty_python"}]

      conn
      |> add_session_cookie(cookie, PhoenixTest.Endpoint.session_options())
      |> visit("/page/session")
      |> assert_has("#form-data", text: "secret: monty_python")
    end
  end

  describe "clear_cookies/2" do
    test "removes all cookies", %{conn: conn} do
      conn
      |> add_cookies([[name: "name", value: "42"]])
      |> visit("/page/cookies")
      |> assert_has("#form-data", text: "name: 42")
      |> clear_cookies()
      |> visit("/page/cookies")
      |> refute_has("#form-data", text: "name: 42")
    end
  end

  describe "javascript logs" do
    test "logs file and line number", %{conn: conn} do
      log =
        capture_log(fn ->
          conn
          |> visit("/page/js_script_console_error")
          |> assert_has("body")
        end)

      assert log =~ "TESTME 42 (http://localhost:4002/page/js_script_console_error:17)"
    end

    test "logs without location if unknown", %{conn: conn} do
      log =
        capture_log(fn ->
          conn
          |> visit("/live/index")
          |> tap(&PhoenixTest.Playwright.Frame.evaluate(&1.frame_id, "console.error('TESTME 42')"))
        end)

      assert log =~ "TESTME 42\n"
    end
  end
end
