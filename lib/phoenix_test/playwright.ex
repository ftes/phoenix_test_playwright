defmodule PhoenixTest.Playwright do
  @moduledoc ~S"""
  Run feature tests in an actual browser, using [PhoenixTest](https://hexdocs.pm/phoenix_test) and [Playwright](https://playwright.dev/).

      defmodule Features.RegisterTest do
        use PhoenixTest.Playwright.Case,
          async: true,                         # async with Ecto sandbox
          parameterize: [                      # run in multiple browsers in parallel
            %{browser_pool: :chromium},
            %{browser_pool: :firefox}
          ]

        @tag trace: :open                      # replay in interactive viewer
        test "register", %{conn: conn} do
          conn
          |> visit(~p"/")
          |> click_link("Register")
          |> fill_in("Email", with: "f@ftes.de")
          |> click_button("Create an account")
          |> assert_has(".error", text: "required")
          |> screenshot("error.png", full_page: true)
        end
      end

  Please [get in touch](https://ftes.de) with feedback of any shape and size.

  Enjoy! Freddy.

  P.S. Looking for a standalone Playwright client? See `PlaywrightEx`.

  See the [README](readme.html) for getting started, configuration, and troubleshooting.

  ## Missing Playwright features
  This module includes functions that are not part of the PhoenixTest protocol, e.g. `screenshot/3` and `click_link/4`.

  But it does not wrap the entire Playwright API, which is quite large.
  You should be able to add any missing functionality yourself
  using `PhoenixTest.unwrap/2`, [`Frame`](`PlaywrightEx.Frame`), [`Selector`](`PlaywrightEx.Selector`),
  and the [Playwright code](https://github.com/microsoft/playwright/blob/main/packages/playwright-core/src/client/frame.ts).

  If you think others might benefit, please [open a PR](https://github.com/ftes/phoenix_test_playwright/pulls).

  Here is some inspiration:
      def choose_styled_radio_with_hidden_input_button(conn, label, opts \\ []) do
        opts = Keyword.validate!(opts, exact: true)
        PhoenixTest.Playwright.click(conn, PlaywrightEx.Selector.text(label, opts))
      end

      def assert_a11y(conn) do
        PlaywrightEx.Frame.evaluate(conn.frame_id, expression: A11yAudit.JS.axe_core(), timeout: timeout())
        {:ok, json} = PlaywrightEx.Frame.evaluate(conn.frame_id, expression: "axe.run()", timeout: timeout())
        results = A11yAudit.Results.from_json(json)
        A11yAudit.Assertions.assert_no_violations(results)

        conn
      end

      def within_iframe(conn, selector \\ "iframe", fun) when is_function(fun, 1) do
        within(conn, "#{selector} >> internal:control=enter-frame", fun)
      end

      # |> assert_download("Wonderwall.pdf", &click_button(&1, "Download PDF"))
      def assert_download(conn, filename, fun) do
        test_pid = self()

        conn
        |> unwrap(fn %{page_id: page_id} ->
          spawn_link(fn ->
            PlaywrightEx.subscribe(page_id)

            receive do
              {:playwright_msg, %{method: :download, params: params}} ->
                send(test_pid, {:download, params.suggested_filename})
            end
          end)
        end)
        |> fun.()
        |> unwrap(fn _ ->
          assert_receive {:download, ^filename}, 500
        end)
      end
  """

  import ExUnit.Assertions

  alias PhoenixTest.Assertions
  alias PhoenixTest.OpenBrowser
  alias PhoenixTest.Playwright.Config
  alias PhoenixTest.Playwright.CookieArgs
  alias PhoenixTest.Playwright.EventListener
  alias PlaywrightEx.BrowserContext
  alias PlaywrightEx.Dialog
  alias PlaywrightEx.Frame
  alias PlaywrightEx.Page
  alias PlaywrightEx.Selector
  alias PlaywrightEx.Tracing

  require Logger

  defstruct [
    :context_id,
    :page_id,
    :frame_id,
    :tracing_id,
    :dialog_listener_pid,
    :last_input_selector,
    within: :none
  ]

  @opaque t :: %__MODULE__{}
  @type css_selector :: String.t()
  @type playwright_selector :: String.t()
  @type selector :: playwright_selector() | css_selector()

  @timeout_opt [type: :non_neg_integer, doc: "Maximum wait time in milliseconds. Defaults to the configured timeout."]

  @exact_opt_schema [type: :boolean, default: false, doc: "Exact or substring text match."]
  @exact_opts_schema [exact: @exact_opt_schema, timeout: @timeout_opt]

  @endpoint Application.compile_env(:phoenix_test, :endpoint)

  @doc false
  def build(%{context_id: context_id, page_id: page_id, frame_id: frame_id, tracing_id: tracing_id, config: config}) do
    %__MODULE__{
      context_id: context_id,
      page_id: page_id,
      frame_id: frame_id,
      tracing_id: tracing_id,
      dialog_listener_pid: start_dialog_listener(page_id, config[:accept_dialogs])
    }
  end

  defp start_dialog_listener(page_id, auto_accept?) do
    filter = &match?(%{method: :__create__, params: %{type: "Dialog"}}, &1)
    callback = &if(auto_accept?, do: {:ok, _} = Dialog.accept(&1.params.guid, timeout: timeout()))
    args = %{guid: page_id, filter: filter, callback: callback}
    ExUnit.Callbacks.start_supervised!({EventListener, args}, id: "#{page_id}-dialog-listener")
  end

  @retry_interval to_timeout(millisecond: 10)
  @doc false
  def retry(fun, remaining) when remaining <= 0, do: fun.()

  def retry(fun, remaining) do
    fun.()
  rescue
    ExUnit.AssertionError ->
      Process.sleep(@retry_interval)
      retry(fun, remaining - @retry_interval)
  end

  @doc """
  Label a step in the Playwright trace.

  This is useful for marking custom helper functions or complex multi-step operations
  so they appear as distinct steps in the trace viewer for easier debugging.
  Steps can be nested.
  Their source location is noted in the trace.

  ## Examples

      def complete_checkout(conn, user_email) do
        conn
        |> sign_in_as(user_email)
        |> step("Check out", fn conn ->
          conn
          |> step("Fill shipping information", fn conn ->
            conn
            |> fill_in("Address", with: "123 Main St")
            |> fill_in("City", with: "Portland")
            |> click_button("Continue")
          end)
          |> step("Fill payment information", fn conn ->
            conn
            |> fill_in("Card number", with: "4242424242424242")
            |> fill_in("CVV", with: "123")
            |> click_button("Place order")
          end)
        end)
      end

      defp sign_in_as(conn, user_email) do
        conn
        |> step("Sign in as \#{user_email}", fn conn ->
          conn
          |> fill_in("Email", with: user_email)
          |> fill_in("Password", with: "password123")
          |> click_button("Sign In")
        end)
      end
  """
  defmacro step(conn, title, fun) do
    caller_location = [file: Path.absname(__CALLER__.file), line: __CALLER__.line]

    quote bind_quoted: [conn: conn, title: title, fun: fun, caller_location: caller_location] do
      Tracing.group(
        conn.tracing_id,
        [
          name: title,
          location: caller_location,
          timeout: Config.global(:timeout)
        ],
        fn -> fun.(conn) end
      )

      conn
    end
  end

  @doc false
  def visit(conn, path), do: visit(conn, path, [])

  @visit_opts_schema [timeout: @timeout_opt]

  @doc """
  Like `PhoenixTest.visit/2`, but with a custom `timeout`.

  ## Options
  #{NimbleOptions.docs(@visit_opts_schema)}
  """
  @spec visit(t(), String.t(), [unquote(NimbleOptions.option_typespec(@visit_opts_schema))]) :: t()
  def visit(conn, path, opts) do
    opts = NimbleOptions.validate!(opts, @visit_opts_schema)
    tap(conn, &({:ok, _} = Frame.goto(&1.frame_id, opts |> ensure_timeout() |> Keyword.put(:url, path))))
  end

  @doc """
  Add cookies to the browser context, using `Plug.Conn.put_resp_cookie/3`

  Note that for signed cookies the signing salt is **not** configurable.
  As such, this function is not appropriate for signed `Plug.Session` cookies.
  For signed session cookies, use `add_session_cookie/3`

    A cookie's value must be a binary unless the cookie is signed/encrypted

  ## Cookie fields

  | key          | type        | description |
  | -----------  | ----------- | ----------- |
  | `:name`      | `binary()`  | |
  | `:value`     | `binary()`  | |
  | `:url`       | `binary()`  | *(optional)* either url or domain / path are required |
  | `:domain`    | `binary()`  | *(optional)* either url or domain / path are required |
  | `:path`      | `binary()`  | *(optional)* either url or domain / path are required |
  | `:max_age`   | `float()`   | *(optional)* The cookie max age, in seconds. |
  | `:http_only` | `boolean()` | *(optional)* |
  | `:secure`    | `boolean()` | *(optional)* |
  | `:encrypt`   | `boolean()` | *(optional)* |
  | `:sign`      | `boolean()` | *(optional)* |
  | `:same_site` | `binary()`  | *(optional)* one of "Strict", "Lax", "None" |

  Two of the cookie fields mean nothing to Playwright. These are:

  1. `:encrypt`
  2. `:sign`

  The `:max_age` cookie field means the same thing as documented in `Plug.Conn.put_resp_cookie/4`.
  The `:max_age` value is used to infer the correct `expires` value that Playwright requires.

  See https://playwright.dev/docs/api/class-browsercontext#browser-context-add-cookies
  """
  def add_cookies(conn, cookies) do
    cookies = Enum.map(cookies, &CookieArgs.from_cookie/1)
    tap(conn, &({:ok, _} = BrowserContext.add_cookies(&1.context_id, cookies: cookies, timeout: timeout())))
  end

  @clear_cookies_opts_schema [timeout: @timeout_opt]

  @doc """
  Removes all cookies from the context.

  ## Options
  #{NimbleOptions.docs(@clear_cookies_opts_schema)}
  """
  @spec clear_cookies(t(), [unquote(NimbleOptions.option_typespec(@clear_cookies_opts_schema))]) :: t()
  def clear_cookies(conn, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @clear_cookies_opts_schema)
    tap(conn, &({:ok, _} = BrowserContext.clear_cookies(&1.context_id, ensure_timeout(opts))))
  end

  @doc """
  Add a `Plug.Session` cookie to the browser context.

  This is useful for emulating a logged-in user.

  Note that that the cookie `:value` must be a map, since we are using
  `Plug.Conn.put_session/3` to write each of value's key-value pairs
  to the cookie.

  The `session_options` are exactly the same as the opts used when
  writing `plug Plug.Session` in your router/endpoint module.

  ## Examples
      |> add_session_cookie(
        [value: %{user_token: Accounts.generate_user_session_token(user)}],
        MyAppWeb.Endpoint.session_options()
      )
  """
  def add_session_cookie(conn, cookie, session_options) do
    cookie = CookieArgs.from_session_options(cookie, session_options)
    tap(conn, &({:ok, _} = BrowserContext.add_cookies(&1.context_id, cookies: [cookie], timeout: timeout())))
  end

  @screenshot_opts_schema [
    full_page: [
      type: :boolean,
      default: true
    ],
    omit_background: [
      type: :boolean,
      default: false,
      doc: "Only applicable to .png images."
    ],
    timeout: @timeout_opt
  ]

  @doc """
  Takes a screenshot of the current page and saves it to the given file path.

  The file type will be inferred from the file extension on the path you provide.
  The file is saved in `:screenshot_dir`, see `PhoenixTest.Playwright.Config`.

  ## Options
  #{NimbleOptions.docs(@screenshot_opts_schema)}

  ## Examples
      |> screenshot("my-screenshot.png")
      |> screenshot("my-test/my-screenshot.jpg")
  """
  @spec screenshot(t(), String.t(), [
          unquote(NimbleOptions.option_typespec(@screenshot_opts_schema))
        ]) :: t()
  def screenshot(conn, file_path, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @screenshot_opts_schema)

    dir = Config.global(:screenshot_dir)
    File.mkdir_p!(dir)

    path = Path.join(dir, file_path)
    {:ok, binary_img} = Page.screenshot(conn.page_id, ensure_timeout(opts))
    File.write!(path, Base.decode64!(binary_img))

    conn
  end

  @type_opts_schema [
    delay: [
      type: :non_neg_integer,
      default: 0,
      doc: "Time to wait between key presses in milliseconds."
    ],
    timeout: @timeout_opt
  ]
  @doc """
  Focuses the matching element and simulates user typing.

  In most cases, you should use `PhoenixTest.fill_in/4` instead.

  ## Options
  #{NimbleOptions.docs(@type_opts_schema)}

  ## Examples
      |> type("#id", "some text")
      |> type(Selector.role("heading", "Untitled"), "New title")
  """
  @spec type(t(), selector(), String.t(), [
          unquote(NimbleOptions.option_typespec(@type_opts_schema))
        ]) :: t()
  def type(conn, selector, text, opts \\ []) when is_binary(text) do
    opts =
      opts
      |> NimbleOptions.validate!(@type_opts_schema)
      |> Keyword.merge(selector: selector, text: text)
      |> ensure_timeout()

    conn.frame_id
    |> Frame.type(opts)
    |> handle_response(selector)

    conn
  end

  @press_opts_schema [
    delay: [
      type: :non_neg_integer,
      default: 0,
      doc: "Time to wait between keydown and keyup in milliseconds."
    ],
    timeout: @timeout_opt
  ]
  @doc """
  Focuses the matching element and presses a combination of the keyboard keys.

  Use `type/4` if you don't need to press special keys.

  Examples of [supported keys](https://developer.mozilla.org/en-US/docs/Web/API/UI_Events/Keyboard_event_key_values):
  `F1 - F12, Digit0- Digit9, KeyA- KeyZ, Backquote, Minus, Equal, Backslash, Backspace, Tab, Delete, Escape, ArrowDown, End, Enter, Home, Insert, PageDown, PageUp, ArrowRight, ArrowUp`

  Modifiers are also supported:
  `Shift, Control, Alt, Meta, ShiftLeft, ControlOrMeta`

  Combinations are also supported:
  `Control+o, Control++, Control+Shift+T`

  ## Options
  #{NimbleOptions.docs(@press_opts_schema)}

  ## Examples
      |> press("#id", "Control+Shift+T")
      |> press(Selector.button("Submit"), "Enter")
  """
  @spec press(t(), selector(), String.t(), [
          unquote(NimbleOptions.option_typespec(@press_opts_schema))
        ]) :: t()
  def press(conn, selector, key, opts \\ []) when is_binary(key) do
    opts =
      opts
      |> NimbleOptions.validate!(@press_opts_schema)
      |> Keyword.merge(selector: selector, key: key)
      |> ensure_timeout()

    conn.frame_id
    |> Frame.press(opts)
    |> handle_response(selector)

    conn
  end

  @drag_opts_schema [
    to: [
      type_spec: quote(do: selector()),
      type_doc: "`t:selector/0`",
      required: true,
      doc: "The target selector."
    ],
    playwright: [
      type: :keyword_list,
      default: [],
      doc:
        "Additional options passed to [frame.dragAndDrop](https://playwright.dev/docs/api/class-frame#frame-drag-and-drop)."
    ],
    timeout: @timeout_opt
  ]

  @doc """
  Drag and drop a source element to a target element.

  ## Options
  #{NimbleOptions.docs(@drag_opts_schema)}

  ## Examples
      |> drag("#source", to: "#target")
      |> drag(Selector.text("Draggable"), to: Selector.text("Target"))
  """
  @spec drag(t(), selector(), [
          unquote(NimbleOptions.option_typespec(@drag_opts_schema))
        ]) :: t()
  def drag(conn, source_selector, opts) do
    {target_selector, opts} = opts |> NimbleOptions.validate!(@drag_opts_schema) |> Keyword.pop!(:to)

    source_selector = conn |> maybe_within() |> Selector.concat(source_selector)
    target_selector = conn |> maybe_within() |> Selector.concat(target_selector)

    opts =
      Keyword.merge(
        [source: source_selector, target: target_selector, timeout: timeout(opts)],
        Keyword.fetch!(opts, :playwright)
      )

    conn.frame_id
    |> Frame.drag_and_drop(opts)
    |> handle_response(source_selector)

    conn
  end

  @doc false
  def assert_path(conn, path, opts \\ []) do
    if opts[:query_params] do
      retry(fn -> Assertions.assert_path(conn, path, opts) end, timeout(opts))
    else
      retry(fn -> Assertions.assert_path(conn, path) end, timeout(opts))
    end
  end

  @doc false
  def refute_path(conn, path, opts \\ []) do
    if opts[:query_params] do
      retry(fn -> Assertions.refute_path(conn, path, opts) end, timeout(opts))
    else
      retry(fn -> Assertions.refute_path(conn, path) end, timeout(opts))
    end
  end

  @doc false
  def assert_has(conn, "title") do
    if not has_title?(conn, text: ""), do: flunk("Page does not have a title")
    conn
  end

  def assert_has(conn, selector), do: assert_has(conn, selector, [])

  @doc false
  def assert_has(conn, "title", opts) do
    if not has_title?(conn, opts), do: flunk("Page title does not match")
    conn
  end

  def assert_has(conn, selector, opts) do
    if not found?(conn, selector, opts), do: flunk("Could not find element \"#{selector}\" #{inspect(opts)}")
    conn
  end

  @doc false
  def refute_has(conn, "title") do
    if not has_title?(conn, text: ""), do: flunk("Page has a title")
    conn
  end

  def refute_has(conn, selector), do: refute_has(conn, selector, [])

  @doc false
  def refute_has(conn, "title", opts) do
    if not has_title?(conn, opts, is_not: true), do: flunk("Page title matches")
    conn
  end

  def refute_has(conn, selector, opts) do
    if found?(conn, selector, opts, is_not: true), do: flunk("Found element \"#{selector}\" #{inspect(opts)}")
    conn
  end

  defp has_title?(conn, opts, params \\ []) do
    {text, opts} = opts |> Keyword.validate!([:text, exact: false]) |> Keyword.pop!(:text)

    params =
      Keyword.merge(
        [
          expression: "to.have.title",
          expected_text: [%{string: text, match_substring: not opts[:exact]}],
          timeout: timeout(opts)
        ],
        params
      )

    {:ok, matches?} = Frame.expect(conn.frame_id, params)
    matches?
  end

  defp found?(conn, selector, opts, other_opts \\ []) do
    other_opts = Keyword.validate!(other_opts, is_not: false)

    selector =
      conn
      |> maybe_within()
      |> Selector.concat(Selector.css(selector))
      |> Selector.and(Selector.label(opts[:label], exact: true))
      |> Selector.concat("visible=true")
      |> Selector.concat(Selector.text(opts[:text], opts))
      |> Selector.concat(Selector.value(opts[:value]))

    params =
      case Map.new(opts) do
        %{count: _, at: _} ->
          raise(ArgumentError, message: "Options `count` and `at` can not be used together")

        %{count: count} ->
          [expression: "to.have.count", expected_number: count, selector: Selector.build(selector)]

        _ ->
          selector = Selector.concat(selector, Selector.at(opts[:at] || 0))
          [expression: "to.be.visible", selector: selector]
      end

    params = [timeout: timeout(opts)] |> Keyword.merge(other_opts) |> Keyword.merge(params)
    {:ok, found?} = Frame.expect(conn.frame_id, params)
    found?
  end

  @doc """
  Handle browser dialogs (`alert()`, `confirm()`, `prompt()`) while executing the inner function.

  *Note:* Add `@tag accept_dialogs: false` before tests that call this function.
  Otherwise, all dialogs are accepted by default.

  ## Callback return values
  The callback may return one of these values:
  - `:accept` -> accepts confirmation dialog
  - `{:accept, prompt_text}` -> accepts prompt dialog with text
  - `:dismiss` -> dismisses dialog
  - Any other value will ignore the dialog

  ## Examples
      @tag accept_dialogs: false
      test "conditionally handle dialog", %{conn: conn} do
      conn
        |> visit("/")
        |> with_dialog(
          fn
            %{message: "Are you sure?"} -> :accept
            %{message: "Enter the magic number"} -> {:accept, "42"}
            %{message: "Self destruct?"} -> :dismiss
          end,
          fn conn ->
            conn
            |> click_button("Delete")
            |> assert_has(".flash", text: "Deleted")
          end
        end)
      end
  """
  def with_dialog(session, callback, fun) when is_function(callback, 1) and is_function(fun, 1) do
    event_callback = fn %{params: %{guid: guid, initializer: %{message: message}}} ->
      {:ok, _} =
        case callback.(%{guid: guid, message: message}) do
          :accept -> Dialog.accept(guid, timeout: timeout())
          {:accept, prompt_text} -> Dialog.accept(guid, prompt_text: prompt_text, timeout: timeout())
          :dismiss -> Dialog.dismiss(guid, timeout: timeout())
          _ -> {:ok, :ignore}
        end
    end

    session
    |> tap(&EventListener.push_callback(&1.dialog_listener_pid, event_callback))
    |> fun.()
    |> tap(&EventListener.pop_callback(&1.dialog_listener_pid))
  end

  @doc false
  def render_page_title(conn) do
    case Frame.title(conn.frame_id, timeout: timeout()) do
      {:ok, ""} -> nil
      {:ok, title} -> title
    end
  end

  @doc false
  def render_html(conn) do
    selector = conn |> maybe_within() |> Selector.build()
    {:ok, html} = Frame.inner_html(conn.frame_id, selector: selector, timeout: timeout())
    LazyHTML.from_document(html)
  end

  @doc """
  See `click/4`.
  """
  @spec click(t(), selector()) :: t()
  def click(conn, selector) do
    conn.frame_id
    |> Frame.click(selector: selector, timeout: timeout())
    |> handle_response(selector)

    conn
  end

  @doc """
  Click an element that is not a link or button.
  Otherwise, use `click_link/4` and `click_button/4`.

  ## Options
  #{NimbleOptions.docs(@exact_opts_schema)}

  ## Examples
      |> click(Selector.menuitem("Edit"))
      |> click("summary", "(expand)", exact: false)
  """
  @spec click(t(), selector(), String.t(), [
          unquote(NimbleOptions.option_typespec(@exact_opts_schema))
        ]) :: t()
  def click(conn, selector, text, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @exact_opts_schema)

    selector =
      conn
      |> maybe_within()
      |> Selector.concat(selector)
      |> Selector.concat(Selector.text(text, opts))

    conn.frame_id
    |> Frame.click(selector: selector, timeout: timeout(opts))
    |> handle_response(selector)

    conn
  end

  @doc """
  Like `PhoenixTest.click_link/3`, but allows exact text match.

  ## Options
  #{NimbleOptions.docs(@exact_opts_schema)}
  """
  def click_link(conn, selector \\ nil, text, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @exact_opts_schema)

    selector =
      conn
      |> maybe_within()
      |> Selector.concat(
        case selector do
          nil -> Selector.link(text, opts)
          css -> css |> Selector.css() |> Selector.concat(Selector.text(text, opts))
        end
      )
      |> Selector.build()

    conn.frame_id
    |> Frame.click(selector: selector, timeout: timeout(opts))
    |> handle_response(selector)

    conn
  end

  @doc """
  Like `PhoenixTest.click_button/3`, but allows exact text match.

  ## Options
  #{NimbleOptions.docs(@exact_opts_schema)}
  """
  def click_button(conn, selector \\ nil, text, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @exact_opts_schema)

    selector =
      conn
      |> maybe_within()
      |> Selector.concat(
        case selector do
          nil -> Selector.button(text, opts)
          css -> css |> Selector.css() |> Selector.concat(Selector.text(text, opts))
        end
      )
      |> Selector.build()

    conn.frame_id
    |> Frame.click(selector: selector, timeout: timeout(opts))
    |> handle_response(selector)

    conn
  end

  @doc false
  def fill_in(conn, css_selector \\ nil, label, opts) do
    {value, opts} = Keyword.pop!(opts, :with)
    fun = &Frame.fill(conn.frame_id, selector: &1, value: to_string(value), timeout: timeout(opts))
    input(conn, css_selector, label, opts, fun)
  end

  @doc false
  def select(conn, css_selector \\ nil, option_labels, opts) do
    if opts[:exact_option] != true, do: raise("exact_option not implemented")

    {label, opts} = Keyword.pop!(opts, :from)
    options = option_labels |> List.wrap() |> Enum.map(&%{label: &1})
    fun = &Frame.select_option(conn.frame_id, selector: &1, options: options, timeout: timeout(opts))
    input(conn, css_selector, label, opts, fun)
  end

  @doc false
  def check(conn, css_selector \\ nil, label, opts) do
    fun = &Frame.check(conn.frame_id, selector: &1, timeout: timeout(opts))
    input(conn, css_selector, label, opts, fun)
  end

  @doc false
  def uncheck(conn, css_selector \\ nil, label, opts) do
    fun = &Frame.uncheck(conn.frame_id, selector: &1, timeout: timeout(opts))
    input(conn, css_selector, label, opts, fun)
  end

  @doc false
  def choose(conn, css_selector \\ nil, label, opts) do
    fun = &Frame.check(conn.frame_id, selector: &1, timeout: timeout(opts))
    input(conn, css_selector, label, opts, fun)
  end

  @doc false
  def upload(conn, css_selector \\ nil, label, paths, opts) do
    paths = paths |> List.wrap() |> Enum.map(&Path.expand/1)
    fun = &Frame.set_input_files(conn.frame_id, selector: &1, local_paths: paths, timeout: timeout(opts))
    input(conn, css_selector, label, opts, fun)
  end

  defp input(conn, css_selector, label, opts, fun) do
    selector =
      conn
      |> maybe_within()
      |> Selector.concat(
        case css_selector do
          nil -> Selector.label(label, opts)
          css -> css |> Selector.css() |> Selector.and(Selector.label(label, opts))
        end
      )
      |> Selector.concat("visible=true")
      |> Selector.build()

    selector
    |> fun.()
    |> handle_response(selector)

    # trigger phx-change if phx-debounce="blur"
    Frame.blur(conn.frame_id, selector: selector, timeout: timeout(opts))

    %{conn | last_input_selector: selector}
  end

  defp maybe_within(conn) do
    case conn.within do
      :none -> Selector.none()
      selector -> selector
    end
  end

  defp handle_response(result, debug_selector) do
    checkbox_msg = "Clicking the checkbox did not change its state"

    case result do
      {:error, %{error: %{name: "TimeoutError"}} = error} ->
        raise ArgumentError,
              "Could not find element with selector \"#{debug_selector}\"#{timeout_suffix(error)}\n" <>
                more_info(error)

      {:error, %{error: %{message: "Error: strict mode violation: " <> _ = message}}} ->
        short_message = String.replace(message, "Error: strict mode violation: ", "")

        raise ArgumentError, "Found more than one element matching selector \"#{debug_selector}\":\n#{short_message}"

      {:error, %{error: %{name: "Error", message: ^checkbox_msg}}} ->
        :ok

      {:ok, result} ->
        result
    end
  end

  defp timeout_suffix(error) do
    case Regex.scan(~r/Timeout (\d+)ms exceeded./, error.error[:message] || "") do
      [[_, timeout]] -> " within #{String.to_integer(timeout)}ms"
      _ -> ""
    end
  end

  defp more_info(error) do
    case error[:log] do
      log when is_list(log) -> "Playwright log:\n" <> Enum.join(log, "\n")
      _ -> inspect(error, pretty: true)
    end
  end

  @doc false
  def submit(conn) do
    Frame.press(conn.frame_id, selector: conn.last_input_selector, key: "Enter", timeout: timeout())
    conn
  end

  @doc false
  def open_browser(conn, open_fun \\ &OpenBrowser.open_with_system_cmd/1) do
    path = Path.join([System.tmp_dir!(), "phx-test#{System.unique_integer([:monotonic])}.html"])

    # Await any pending navigation
    Process.sleep(100)
    {:ok, raw_html} = Frame.content(conn.frame_id, timeout: timeout())

    fixed_html =
      raw_html
      |> PhoenixTest.Html.parse_document()
      |> PhoenixTest.Html.postwalk(&OpenBrowser.prefix_static_paths(&1, @endpoint))
      |> PhoenixTest.Html.raw()

    File.write!(path, fixed_html)

    open_fun.(path)

    conn
  end

  @evaluate_opts_schema [timeout: @timeout_opt]

  @doc """
  Evaluates a JavaScript expression in the page context.

  When a callback function is given, it receives the JavaScript result. This
  is useful for assertions or side effects without breaking the pipe chain.

  ## Options
  #{NimbleOptions.docs(@evaluate_opts_schema)}

  ## Examples
      conn
      |> evaluate("window.scrollTo(0, document.body.scrollHeight)")

      conn
      |> evaluate("document.title", & assert &1 =~ "Dashboard")
  """
  @spec evaluate(t(), String.t()) :: t()
  @spec evaluate(t(), String.t(), [unquote(NimbleOptions.option_typespec(@evaluate_opts_schema))] | (any() -> any())) ::
          t()
  @spec evaluate(t(), String.t(), [unquote(NimbleOptions.option_typespec(@evaluate_opts_schema))], (any() -> any())) ::
          t()
  def evaluate(conn, expression), do: evaluate(conn, expression, [], & &1)
  def evaluate(conn, expression, fun) when is_function(fun, 1), do: evaluate(conn, expression, [], fun)
  def evaluate(conn, expression, opts) when is_list(opts), do: evaluate(conn, expression, opts, & &1)

  def evaluate(conn, expression, opts, fun) when is_list(opts) and is_function(fun, 1) do
    opts = NimbleOptions.validate!(opts, @evaluate_opts_schema)

    tap(conn, fn conn ->
      case Frame.evaluate(conn.frame_id, expression: expression, timeout: timeout(opts)) do
        {:ok, value} ->
          fun.(value)

        {:error, error} ->
          raise ExUnit.AssertionError,
            message: "JavaScript evaluation failed: #{inspect(expression)}\n\n#{inspect(error)}"
      end
    end)
  end

  @doc """
  See `PhoenixTest.unwrap/2`.

  Invokes `fun` with various Playwright IDs.
  These can be used to interact with the Playwright
  [`BrowserContext`](`PlaywrightEx.BrowserContext`),
  [`Page`](`PlaywrightEx.Page`) and
  [`Frame`](`PlaywrightEx.Frame`).

  ## Examples
      |> unwrap(fn %{page_id: page_id} -> PlaywrightEx.subscribe(page_id) end)
  """
  @spec unwrap(t(), (%{context_id: any(), page_id: any(), frame_id: any()} -> any())) :: t()
  def unwrap(conn, fun) do
    tap(conn, &fun.(Map.take(&1, ~w(context_id page_id frame_id)a)))
  end

  @doc false
  def current_path(conn) do
    case Frame.evaluate(conn.frame_id,
           expression: "window.location.pathname + window.location.search",
           timeout: timeout()
         ) do
      {:ok, path} ->
        path

      {:error, _} ->
        raise ExUnit.AssertionError, message: "Could not read current path (page may be navigating)"
    end
  end

  defp timeout, do: Config.global(:timeout)
  defp timeout(opts), do: Keyword.get_lazy(opts, :timeout, &timeout/0)
  defp ensure_timeout(opts), do: Keyword.put_new_lazy(opts, :timeout, &timeout/0)
end

defimpl PhoenixTest.Driver, for: PhoenixTest.Playwright do
  alias PhoenixTest.Playwright

  defdelegate visit(conn, path), to: Playwright
  defdelegate render_page_title(conn), to: Playwright
  defdelegate render_html(conn), to: Playwright
  defdelegate within(conn, selector, fun), to: PhoenixTest.SessionHelpers
  defdelegate click_link(conn, text), to: Playwright
  defdelegate click_link(conn, selector, text), to: Playwright
  defdelegate click_button(conn, text), to: Playwright
  defdelegate click_button(conn, selector, text), to: Playwright
  defdelegate fill_in(conn, label, opts), to: Playwright
  defdelegate fill_in(conn, selector, label, opts), to: Playwright
  defdelegate select(conn, selector, option, opts), to: Playwright
  defdelegate select(conn, option, opts), to: Playwright
  defdelegate check(conn, selector, label, opts), to: Playwright
  defdelegate check(conn, label, opts), to: Playwright
  defdelegate uncheck(conn, selector, label, opts), to: Playwright
  defdelegate uncheck(conn, label, opts), to: Playwright
  defdelegate choose(conn, selector, label, opts), to: Playwright
  defdelegate choose(conn, label, opts), to: Playwright
  defdelegate upload(conn, selector, label, path, opts), to: Playwright
  defdelegate upload(conn, label, path, opts), to: Playwright
  defdelegate submit(conn), to: Playwright
  defdelegate open_browser(conn), to: Playwright
  defdelegate open_browser(conn, open_fun), to: Playwright
  defdelegate unwrap(conn, fun), to: Playwright
  defdelegate current_path(conn), to: Playwright

  defdelegate assert_has(conn, selector), to: Playwright
  defdelegate assert_has(conn, selector, opts), to: Playwright
  defdelegate refute_has(conn, selector), to: Playwright
  defdelegate refute_has(conn, selector, opts), to: Playwright

  defdelegate assert_path(conn, path), to: Playwright
  defdelegate assert_path(conn, path, opts), to: Playwright
  defdelegate refute_path(conn, path), to: Playwright
  defdelegate refute_path(conn, path, opts), to: Playwright
end
