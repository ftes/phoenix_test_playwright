defmodule PhoenixTest.Playwright do
  @moduledoc ~S"""
  Playwright driver for [PhoenixTest](https://hexdocs.pm/phoenix_test).

  This module implements the PhoenixTest driver protocol, running tests in a real browser
  via Playwright. The `conn` in tests is not a `Plug.Conn` but a `%PhoenixTest.Playwright{}`
  struct holding the Playwright session state (page, browser context, etc.).

  It also provides browser-specific functions beyond the standard PhoenixTest API,
  such as `screenshot/3`, `evaluate/2`, `type/4`, `press/4`, and `drag/3`.

  See the [README](README.md) for getting started, configuration, troubleshooting,
  and adding missing Playwright features.
  """

  import ExUnit.Assertions

  alias PhoenixTest.Assertions
  alias PhoenixTest.OpenBrowser
  alias PhoenixTest.Playwright.Browser
  alias PhoenixTest.Playwright.Config
  alias PhoenixTest.Playwright.CookieArgs
  alias PhoenixTest.Playwright.Selector
  alias PlaywrightEx.BrowserContext
  alias PlaywrightEx.Dialog
  alias PlaywrightEx.Download
  alias PlaywrightEx.Expect
  alias PlaywrightEx.ExpectError
  alias PlaywrightEx.Locator
  alias PlaywrightEx.Page
  alias PlaywrightEx.PlaywrightError
  alias PlaywrightEx.TimeoutError
  alias PlaywrightEx.Tracing

  defstruct [
    :context,
    :page,
    :dialog_listener,
    :last_input_selector,
    within: :none
  ]

  @typedoc "A Playwright session, passed through tests as `conn`."
  @opaque t :: %__MODULE__{}
  @typedoc "A CSS selector string."
  @type css_selector :: String.t()
  @typedoc "A Playwright selector, typically built with `PhoenixTest.Playwright.Selector`."
  @type playwright_selector :: String.t()
  @typedoc "A CSS string, or a Playwright selector typically built with `PhoenixTest.Playwright.Selector`."
  @type selector :: playwright_selector() | css_selector()

  @timeout_opt [
    type: :timeout,
    doc:
      "Maximum wait in milliseconds. Defaults to the configured timeout. See [Timeouts](`PhoenixTest.Playwright.Config#module-timeouts`)."
  ]

  @exact_opt_schema [type: :boolean, default: false, doc: "Exact or substring text match."]
  @exact_opts_schema [exact: @exact_opt_schema, timeout: @timeout_opt]

  @endpoint Application.compile_env(:phoenix_test, :endpoint)

  @doc false
  @spec build(%{
          required(:context) => BrowserContext.t(),
          required(:page) => Page.t(),
          required(:config) => keyword()
        }) :: t()
  def build(%{context: context, page: page, config: config}) do
    forward_downloads(page, self())

    %__MODULE__{
      context: context,
      page: page,
      dialog_listener: start_dialog_listener(page, config[:accept_dialogs])
    }
  end

  # With no listener at all, Playwright dismisses dialogs. `accept_dialogs: false` must leave them open.
  defp start_dialog_listener(page, auto_accept?) do
    listener = if auto_accept?, do: &(:ok = Dialog.accept(&1)), else: fn _dialog -> :ok end
    Page.on(page, :dialog, listener)
    listener
  end

  defp forward_downloads(page, owner) do
    Page.on(page, :download, &send(owner, {:download, page, &1}))
  end

  @retry_interval to_timeout(millisecond: 10)
  @doc false
  def retry(fun, remaining) when remaining <= 0, do: fun.()

  def retry(fun, remaining) do
    fun.()
  rescue
    ExUnit.AssertionError ->
      Process.sleep(@retry_interval)
      retry(fun, next_retry_timeout(remaining))
  end

  defp next_retry_timeout(:infinity), do: :infinity
  defp next_retry_timeout(remaining), do: remaining - @retry_interval

  @doc group: "Debugging & escape hatches"
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
      tracing = BrowserContext.tracing(conn.context)
      Tracing.group!(tracing, title, location: Map.new(caller_location))

      try do
        fun.(conn)
      after
        Tracing.group_end!(tracing)
      end

      conn
    end
  end

  @doc false
  def visit(conn, path), do: visit(conn, path, [])

  @visit_opts_schema [
    timeout: @timeout_opt,
    referer: [
      type: :string,
      doc:
        "Referer header value. If provided, takes preference over the referer header set via the `extra_http_headers` option to `PlaywrightEx.Browser.new_context/2`."
    ],
    wait_until: [
      type: {:in, ["load", "domcontentloaded", "networkidle", "commit"]},
      default: "load",
      doc: """
      When to consider the operation succeeded. One of:
      - `"load"` (default) — fires when the `load` event is fired.
      - `"domcontentloaded"` — fires when the `DOMContentLoaded` event is fired.
      - `"networkidle"` — **discouraged** — fires when there are no network connections for at least 500 ms. Rely on web assertions instead for testing readiness.
      - `"commit"` — fires when the network response is received and the document has started loading.
      """
    ]
  ]

  @doc group: "Actions"
  @doc """
  Like `PhoenixTest.visit/2`, but with additional options.

  ## Options
  #{NimbleOptions.docs(@visit_opts_schema)}
  """
  @spec visit(t(), String.t(), [unquote(NimbleOptions.option_typespec(@visit_opts_schema))]) :: t()
  def visit(conn, path, opts) do
    opts = opts |> NimbleOptions.validate!(@visit_opts_schema) |> ensure_timeout()

    with {:error, error} <- Page.goto(conn.page, path, opts),
         false <- error.message =~ "Download is starting" do
      raise error
    end

    conn
  end

  @reload_page_opts_schema [timeout: @timeout_opt]

  @doc false
  def reload_page(conn, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @reload_page_opts_schema)
    tap(conn, &Page.reload!(&1.page, ensure_timeout(opts)))
  end

  @doc group: "Cookies"
  @doc """
  Add cookies to the browser context, using `Plug.Conn.put_resp_cookie/4`.

  Note that for signed cookies the signing salt is **not** configurable.
  As such, this function is not appropriate for signed `Plug.Session` cookies.
  For signed session cookies, use `add_session_cookie/3`.

  A cookie's value must be a binary unless the cookie is signed/encrypted.

  ## Cookie fields

  | key          | type        | description |
  | -----------  | ----------- | ----------- |
  | `:name`      | `binary()`  | |
  | `:value`     | `binary()`  | |
  | `:url`       | `binary()`  | *(optional)* either url or domain / path are required |
  | `:domain`    | `binary()`  | *(optional)* either url or domain / path are required |
  | `:path`      | `binary()`  | *(optional)* either url or domain / path are required |
  | `:max_age`   | `integer()` | *(optional)* The cookie max age, in seconds. |
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
  @spec add_cookies(t(), [keyword()]) :: t()
  def add_cookies(conn, cookies) do
    cookies = Enum.map(cookies, &CookieArgs.from_cookie/1)
    bounded!(timeout(), "browserContext.addCookies", fn -> BrowserContext.add_cookies(conn.context, cookies) end)
    conn
  end

  @clear_cookies_opts_schema [timeout: @timeout_opt]

  @doc group: "Cookies"
  @doc """
  Removes all cookies from the context.

  ## Options
  #{NimbleOptions.docs(@clear_cookies_opts_schema)}
  """
  @spec clear_cookies(t(), [unquote(NimbleOptions.option_typespec(@clear_cookies_opts_schema))]) :: t()
  def clear_cookies(conn, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @clear_cookies_opts_schema)
    bounded!(timeout(opts), "browserContext.clearCookies", fn -> BrowserContext.clear_cookies(conn.context) end)
    conn
  end

  @doc group: "Cookies"
  @doc """
  Add a `Plug.Session` cookie to the browser context.

  This is useful for emulating a logged-in user.

  Note that the cookie `:value` must be a map, since we are using
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
  @spec add_session_cookie(t(), keyword(), keyword()) :: t()
  def add_session_cookie(conn, cookie, session_options) do
    cookie = CookieArgs.from_session_options(cookie, session_options)
    bounded!(timeout(), "browserContext.addCookies", fn -> BrowserContext.add_cookies(conn.context, [cookie]) end)
    conn
  end

  @screenshot_opts_schema [
    full_page: [
      type: :boolean,
      default: true
    ],
    omit_background: [
      type: :boolean,
      default: false,
      doc: "Hides the default white background to allow transparency. Ignored for `.jpg` and `.jpeg` images."
    ],
    timeout: @timeout_opt
  ]

  @doc group: "Assertions & screenshots"
  @doc """
  Takes a screenshot of the current page and saves it to the given file path.

  The file type will be inferred from the file extension on the path you provide:
  `.png`, `.jpg`, `.jpeg` or `.webp`. Any other extension raises.
  The file is saved in `:screenshot_dir`, see `PhoenixTest.Playwright.Config`.
  Missing directories are created.

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

    path = Path.join(Config.global(:screenshot_dir), file_path)
    Page.screenshot!(conn.page, ensure_timeout([path: path] ++ opts))

    conn
  end

  # Upstream's `doc` is only the first paragraph.
  @assert_screenshot_doc_additions %{
    animations:
      " finite animations are fast-forwarded to completion, so they'll fire `transitionend` event. Infinite animations are canceled to initial state, and then played over after the screenshot. Defaults to `:disabled`.",
    scale: " Defaults to `:css`."
  }

  # Options are passed on to `Expect.to_have_screenshot/2`. Enums also take strings there.
  @assert_screenshot_opts_schema :to_have_screenshot
                                 |> Expect.__options__()
                                 |> Keyword.drop(~w(path signal)a)
                                 |> Enum.map(fn {name, %{spec: spec, doc: doc}} ->
                                   nodes = spec |> Macro.prewalker() |> Enum.to_list()

                                   enum? =
                                     match?({:|, _, _}, spec) and
                                       Enum.all?(nodes, &(is_atom(&1) or match?({:|, _, _}, &1)))

                                   {type, spec} =
                                     case spec do
                                       _enum when enum? ->
                                         atoms = Enum.filter(nodes, &is_atom/1)

                                         {{:in, atoms ++ Enum.map(atoms, &to_string/1)},
                                          quote(do: String.t() | unquote(spec))}

                                       {:boolean, _, []} ->
                                         {:boolean, spec}

                                       {:integer, _, []} ->
                                         {:integer, spec}

                                       {:number, _, []} ->
                                         {{:or, [:float, :integer]}, spec}

                                       _other ->
                                         {:any, spec}
                                     end

                                   doc = doc <> Map.get(@assert_screenshot_doc_additions, name, "")
                                   {name, type: type, type_spec: spec, type_doc: "`#{Macro.to_string(spec)}`", doc: doc}
                                 end)
                                 |> Keyword.merge(
                                   selector: [
                                     type: :string,
                                     doc: "Scope the screenshot to a CSS or Playwright selector instead of the full page."
                                   ],
                                   mask: [
                                     type: {:list, :string},
                                     doc:
                                       "Specify selectors that should be masked when the screenshot is taken. Masked elements will be overlaid with a pink box `#FF00FF` (customized by `:mask_color`) that completely covers its bounding box."
                                   ],
                                   snapshot_dir: [
                                     type: :string,
                                     doc: "Override the global `:snapshot_dir` config for this call."
                                   ],
                                   timeout: @timeout_opt
                                 )

  @doc group: "Assertions & screenshots"
  @doc """
  Visual regression assertion: compares a screenshot of the current page against a stored baseline.

  `name` is a relative path within `:snapshot_dir` (see `PhoenixTest.Playwright.Config`), including
  the file extension, which must be `.png` or `.webp` — for example `"home.png"` or `"auth/login.png"`.
  Subdirectories are created automatically.

  On first run (no baseline exists), the screenshot is saved as the new baseline, a notice is printed
  and the test passes.
  On subsequent runs, the live screenshot is compared pixel-by-pixel against the baseline.
  On mismatch, a diff image is saved to `<snapshot_dir>/__diff__/<name>` and the test fails.

  To update a baseline, delete the snapshot file and re-run the test.

  Playwright writes its comparison output next to the snapshot, so don't name baselines
  `<name>-actual`, `<name>-expected`, `<name>-previous` or `<name>-diff`.

  ## Options
  #{NimbleOptions.docs(@assert_screenshot_opts_schema)}

  ## Examples
      |> assert_screenshot("home.png")
      |> assert_screenshot("auth/login.png", full_page: false)
      |> assert_screenshot("hero.png", selector: ".hero-section")
  """
  @spec assert_screenshot(t(), String.t(), [unquote(NimbleOptions.option_typespec(@assert_screenshot_opts_schema))]) ::
          t()
  def assert_screenshot(conn, name, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @assert_screenshot_opts_schema)
    {snapshot_dir, opts} = Keyword.pop(opts, :snapshot_dir, Config.global(:snapshot_dir))
    snapshot_path = Path.join(snapshot_dir, name)
    {selector, opts} = Keyword.pop(opts, :selector)
    target = if selector, do: locator(conn, selector), else: conn.page

    opts =
      opts
      |> ensure_timeout()
      |> maybe_convert_mask(conn)
      |> Keyword.put(:path, snapshot_path)

    actual_existed? = snapshot_path |> snapshot_output_path("-actual") |> File.exists?()
    result = Expect.to_have_screenshot(target, opts)
    output_files = snapshot_output_files(result, actual_existed?, snapshot_path)
    diff_written? = keep_only_diff_file(output_files, snapshot_path, Path.join([snapshot_dir, "__diff__", name]))

    case result do
      :ok ->
        conn

      {:error, %ExpectError{message: msg}} when diff_written? ->
        flunk("Screenshot mismatch for #{name}: #{screenshot_diff_summary(msg)}")

      {:error, %ExpectError{message: msg}} ->
        flunk(msg)

      {:error, error} ->
        raise error
    end
  end

  defp screenshot_diff_summary(message) do
    case Regex.run(~r/^\s*(.+ are different\.)\s*$/m, message) do
      [_, summary] -> summary
      nil -> message
    end
  end

  defp maybe_convert_mask(opts, conn) do
    case Keyword.pop(opts, :mask) do
      {nil, opts} -> opts
      {selectors, opts} -> Keyword.put(opts, :mask, Enum.map(selectors, &locator(conn, &1)))
    end
  end

  # The files Playwright wrote next to the snapshot: `-actual` when it writes a baseline, the attachments on failure.
  defp snapshot_output_files(:ok, true = _actual_existed?, _snapshot_path), do: []

  defp snapshot_output_files(:ok, false = _actual_existed?, snapshot_path) do
    [snapshot_output_path(snapshot_path, "-actual")]
  end

  defp snapshot_output_files(
         {:error, %ExpectError{matcherResult: %{attachments: attachments}}},
         _actual_existed?,
         snapshot_path
       ) do
    Enum.map(attachments, &Path.join(Path.dirname(snapshot_path), &1.name))
  end

  defp snapshot_output_files(_result, _actual_existed?, _snapshot_path), do: []

  # Only the diff is of interest, and it goes in a directory that can be gitignored.
  defp keep_only_diff_file(output_files, snapshot_path, diff_path) do
    playwright_diff_path = snapshot_output_path(snapshot_path, "-diff")
    for file <- output_files -- [playwright_diff_path], do: File.rm(file)

    if playwright_diff_path in output_files do
      File.mkdir_p!(Path.dirname(diff_path))
      File.rename!(playwright_diff_path, diff_path)
      true
    else
      false
    end
  end

  defp snapshot_output_path(snapshot_path, suffix) do
    Path.rootname(snapshot_path) <> suffix <> Path.extname(snapshot_path)
  end

  @type_opts_schema [
    delay: [
      type: :non_neg_integer,
      default: 0,
      doc: "Time to wait between key presses in milliseconds."
    ],
    timeout: @timeout_opt
  ]
  @doc group: "Actions"
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
    opts = opts |> NimbleOptions.validate!(@type_opts_schema) |> ensure_timeout()

    conn
    |> locator(selector)
    |> Locator.first()
    |> Locator.press_sequentially(text, opts)
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
  @doc group: "Actions"
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
    opts = opts |> NimbleOptions.validate!(@press_opts_schema) |> ensure_timeout()

    conn
    |> locator(selector)
    |> Locator.first()
    |> Locator.press(key, opts)
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
      doc: "Additional options passed to [locator.dragTo](https://playwright.dev/docs/api/class-locator#locator-drag-to)."
    ],
    timeout: @timeout_opt
  ]

  @doc group: "Actions"
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

    source_selector = Selector.concat(conn.within, source_selector)
    target_selector = Selector.concat(conn.within, target_selector)

    opts = Keyword.merge([timeout: timeout(opts)], Keyword.fetch!(opts, :playwright))

    conn
    |> locator(source_selector)
    |> Locator.drag_to(locator(conn, target_selector), opts)
    |> handle_response(source_selector)

    conn
  end

  @path_assertion_opts_schema [
    query_params: [
      type: {:map, :any, :any},
      doc: "Map of query params to match exactly."
    ],
    timeout: @timeout_opt
  ]

  @doc false
  def assert_path(conn, path, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @path_assertion_opts_schema)

    retry(fn -> Assertions.assert_path(conn, path, opts) end, timeout(opts))
  end

  @doc false
  def refute_path(conn, path, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @path_assertion_opts_schema)

    retry(fn -> Assertions.refute_path(conn, path, opts) end, timeout(opts))
  end

  @doc false
  def assert_has(conn, "title") do
    if not has_title_element?(conn), do: flunk("Page does not have a title")
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
    if has_title_element?(conn, is_not: true) do
      flunk("Expected title not to be present but found: #{inspect(render_page_title(conn))}")
    end

    conn
  end

  def refute_has(conn, selector), do: refute_has(conn, selector, [])

  @doc false
  def refute_has(conn, "title", opts) do
    if has_title?(conn, opts, is_not: true) do
      expected = opts |> Keyword.fetch!(:text) |> ensure_binary()
      flunk("Expected title not to be #{inspect(expected)}")
    end

    conn
  end

  def refute_has(conn, selector, opts) do
    if found?(conn, selector, opts, is_not: true), do: flunk("Found element \"#{selector}\" #{inspect(opts)}")
    conn
  end

  @title_assertion_opts_schema [
    text: [
      type: :any,
      required: true
    ],
    exact: @exact_opt_schema,
    timeout: @timeout_opt
  ]

  @assertion_opts_schema [
    text: [
      type: :any
    ],
    value: [
      type: :any
    ],
    selected: [
      type: :any
    ],
    checked: [
      type: :any
    ],
    label: [
      type: :string
    ],
    exact: @exact_opt_schema,
    count: [
      type: :non_neg_integer
    ],
    at: [
      type: :integer
    ],
    timeout: @timeout_opt
  ]
  @content_assertion_opts [:text, :value, :selected, :checked]

  defp has_title?(conn, opts, other_opts \\ []) do
    {text, opts} = opts |> NimbleOptions.validate!(@title_assertion_opts_schema) |> Keyword.pop!(:text)
    text = ensure_binary(text)
    expected = if opts[:exact], do: text, else: ~r/#{Regex.escape(text)}/

    expect_matches?(conn.page, other_opts[:is_not], &Expect.to_have_title(&1, expected, timeout: timeout(opts)))
  end

  defp has_title_element?(conn, other_opts \\ []) do
    conn
    |> locator(Selector.css("title"))
    |> expect_matches?(other_opts[:is_not], &Expect.to_be_attached(&1, timeout: timeout()))
  end

  defp found?(conn, selector, opts, other_opts \\ []) do
    opts = opts |> validate_assertion_opts!() |> normalize_assertion_content()
    other_opts = Keyword.validate!(other_opts, is_not: false)

    if opts[:count] && opts[:at] do
      raise(ArgumentError, message: "Options `count` and `at` can not be used together")
    end

    selector =
      conn.within
      |> Selector.concat(Selector.css(selector))
      |> Selector.concat(assertion_position(opts[:at]))
      |> Selector.and(Selector.label(opts[:label], opts))
      |> Selector.and(checked_selector(opts[:checked]))
      |> selector_has(selected_selector(opts[:selected]))
      |> Selector.concat(Selector.text(opts[:text], opts))
      |> Selector.concat(Selector.value(opts[:value]))
      |> Selector.visible()

    case Map.new(opts) do
      %{count: count} ->
        conn
        |> locator(Selector.build(selector))
        |> expect_matches?(other_opts[:is_not], &Expect.to_have_count(&1, count, timeout: timeout(opts)))

      _ ->
        conn
        |> locator(Selector.concat(selector, if(opts[:at], do: :none, else: Selector.at(0))))
        |> expect_matches?(other_opts[:is_not], &Expect.to_be_visible(&1, timeout: timeout(opts)))
    end
  end

  # Whether the positive assertion holds, after waiting for the expected outcome.
  # Only a timed out expectation is a boolean result. Other failures, such as strict mode violations, must raise.
  defp expect_matches?(actual, is_not, matcher) do
    case matcher.(if(is_not, do: Expect.not_(actual), else: actual)) do
      :ok -> !is_not
      {:error, %ExpectError{matcherResult: %{timeout: _}}} -> !!is_not
      {:error, error} -> raise error
    end
  end

  defp validate_assertion_opts!(opts) do
    opts = NimbleOptions.validate!(opts, @assertion_opts_schema)

    case Keyword.get(opts, :checked) do
      checked when is_boolean(checked) or is_nil(checked) ->
        :ok

      checked ->
        raise ArgumentError, "Expected :checked to be true or false, got #{inspect(checked)}"
    end

    if Keyword.has_key?(opts, :text) and Keyword.has_key?(opts, :label) do
      raise ArgumentError, "Cannot provide :label with :text to assertions"
    end

    content_opts = Enum.filter(@content_assertion_opts, &Keyword.has_key?(opts, &1))

    if length(content_opts) > 1 do
      raise ArgumentError, "Cannot pass more than one of options :text, :value, :selected, :checked to assertions"
    end

    opts
  end

  defp normalize_assertion_content(opts) do
    Enum.reduce([:text, :value, :selected], opts, fn key, opts ->
      if Keyword.has_key?(opts, key), do: Keyword.update!(opts, key, &ensure_binary/1), else: opts
    end)
  end

  defp assertion_position(nil), do: :none
  defp assertion_position(at), do: Selector.at(at - 1)

  defp checked_selector(nil), do: :none
  defp checked_selector(true), do: Selector.css(":checked")
  defp checked_selector(false), do: Selector.css(":not(:checked)")

  defp selected_selector(nil), do: :none

  defp selected_selector(selected) do
    "option:checked"
    |> Selector.css()
    |> Selector.concat(Selector.text(selected, exact: true))
  end

  defp selector_has(selector, :none), do: selector
  defp selector_has(selector, has_selector), do: Selector.has(selector, has_selector)

  @doc false
  def assert_download(%{page: page} = conn, filename_or_fun) do
    download =
      receive do
        {:download, ^page, download} ->
          path = download_artifact(download)
          filename = Download.suggested_filename(download)

          %PhoenixTest.FileDownload{
            mime_type: MIME.from_path(filename),
            name: filename,
            content: File.read!(path)
          }
      after
        Config.global(:timeout) -> flunk("No download detected")
      end

    case filename_or_fun do
      filename when is_binary(filename) -> assert download.name == filename
      fun when is_function(fun, 1) -> fun.(download)
    end

    conn
  end

  defp download_artifact(download) do
    path = Path.join(System.tmp_dir!(), "phoenix-test-download-#{System.unique_integer([:positive])}")

    case bounded(timeout(), "download.saveAs", fn -> Download.save_as(download, path) end) do
      :ok -> path
      {:error, error} -> raise ExUnit.AssertionError, message: "Download failed: #{Exception.message(error)}"
    end
  end

  @doc group: "Actions"
  @doc """
  Handle browser dialogs (`alert()`, `confirm()`, `prompt()`) while executing the inner function.

  For the duration of `fun`, `callback` takes over from the `accept_dialogs` behaviour.

  ## Callback return values
  The callback receives a map with `:message` (the dialog text) and `:dialog`
  (a `t:PlaywrightEx.Dialog.t/0`), and may return one of these values:
  - `:accept` -> accepts confirmation dialog
  - `{:accept, prompt_text}` -> accepts prompt dialog with text
  - `:dismiss` -> dismisses dialog
  - Any other value will ignore the dialog

  ## Examples
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
        )
      end
  """
  @spec with_dialog(t(), (%{dialog: Dialog.t(), message: String.t()} -> any()), (t() -> t())) :: t()
  def with_dialog(session, callback, fun) when is_function(callback, 1) and is_function(fun, 1) do
    listener = fn dialog ->
      :ok =
        case callback.(%{dialog: dialog, message: Dialog.message(dialog)}) do
          :accept -> Dialog.accept(dialog)
          {:accept, prompt_text} -> Dialog.accept(dialog, prompt_text)
          :dismiss -> Dialog.dismiss(dialog)
          _ -> :ok
        end
    end

    outer = session.dialog_listener
    replace_dialog_listener(session.page, outer, listener)

    try do
      %{fun.(%{session | dialog_listener: listener}) | dialog_listener: outer}
    after
      replace_dialog_listener(session.page, listener, outer)
    end
  end

  # Add before remove: while a page has no dialog listener, Playwright dismisses its dialogs.
  defp replace_dialog_listener(page, old, new) do
    Page.on(page, :dialog, new)
    Page.off(page, :dialog, old)
  end

  @doc false
  def render_page_title(conn) do
    case bounded!(timeout(), "page.title", fn -> Page.title(conn.page) end) do
      "" -> nil
      title -> title
    end
  end

  @doc false
  def render_html(conn) do
    selector = Selector.build(conn.within)
    html = conn |> locator(selector) |> Locator.first() |> Locator.inner_html!(timeout: timeout())
    LazyHTML.from_document(html)
  end

  @doc group: "Actions"
  @doc """
  Click the element matching `selector`.

  See `click/4` to also match on text.
  """
  @spec click(t(), selector()) :: t()
  def click(conn, selector) do
    conn
    |> locator(selector)
    |> Locator.click(timeout: timeout())
    |> handle_response(selector)

    conn
  end

  @doc group: "Actions"
  @doc """
  Click the element matching `selector` that contains visible `text`.

  Prefer `click_link/4` and `click_button/4` for links and buttons.

  The element matching `selector` remains the click target when `text` is nested
  inside it.

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
      conn.within
      |> Selector.concat(selector)
      |> Selector.has(Selector.visible(Selector.text(text, opts)))

    conn
    |> locator(selector)
    |> Locator.click(timeout: timeout(opts))
    |> handle_response(selector)

    conn
  end

  @doc group: "Actions"
  @doc """
  Like `PhoenixTest.click_link/3`, but allows exact text match.

  ## Options
  #{NimbleOptions.docs(@exact_opts_schema)}
  """
  @spec click_link(t(), selector() | nil, String.t(), [
          unquote(NimbleOptions.option_typespec(@exact_opts_schema))
        ]) :: t()
  def click_link(conn, selector \\ nil, text, opts \\ []) do
    click_role(conn, selector, text, opts, &Selector.link/2)
  end

  @doc group: "Actions"
  @doc """
  Like `PhoenixTest.click_button/3`, but allows exact text match.

  ## Options
  #{NimbleOptions.docs(@exact_opts_schema)}
  """
  @spec click_button(t(), selector() | nil, String.t(), [
          unquote(NimbleOptions.option_typespec(@exact_opts_schema))
        ]) :: t()
  def click_button(conn, selector \\ nil, text, opts \\ []) do
    click_role(conn, selector, text, opts, &Selector.button/2)
  end

  defp click_role(conn, selector, text, opts, role_selector) do
    opts = NimbleOptions.validate!(opts, @exact_opts_schema)

    selector =
      conn.within
      |> Selector.concat(
        case selector do
          nil -> role_selector.(text, opts)
          css -> css |> Selector.css() |> Selector.concat(Selector.text(text, opts))
        end
      )
      |> Selector.build()

    conn
    |> locator(selector)
    |> Locator.click(timeout: timeout(opts))
    |> handle_response(selector)

    conn
  end

  @fill_in_opts_schema [
    with: [
      type: :any,
      required: true,
      doc: "Value to fill into the input."
    ],
    exact: @exact_opt_schema,
    timeout: @timeout_opt
  ]

  @select_opts_schema [
    from: [
      type: :string,
      required: true,
      doc: "Label of the select field."
    ],
    exact: @exact_opt_schema,
    exact_option: [
      type: :boolean,
      default: true,
      doc: "Whether to match option text exactly."
    ],
    timeout: @timeout_opt
  ]

  @doc false
  def fill_in(conn, css_selector \\ nil, label, opts) do
    opts = NimbleOptions.validate!(opts, @fill_in_opts_schema)
    {value, opts} = Keyword.pop!(opts, :with)
    fun = &Locator.fill(&1, to_string(value), timeout: timeout(opts))
    input(conn, css_selector || "input:not([type='hidden']),textarea", label, opts, fun, blur: true)
  end

  @doc false
  def select(conn, css_selector \\ nil, option_labels, opts) do
    # PhoenixTest.select/3 passes the option as `option_labels` and leaves this duplicate key in opts.
    opts = Keyword.delete(opts, :option)
    opts = NimbleOptions.validate!(opts, @select_opts_schema)

    if opts[:exact_option] != true, do: raise("exact_option not implemented")

    {label, opts} = Keyword.pop!(opts, :from)
    options = option_labels |> List.wrap() |> Enum.map(&%{label: &1})
    fun = &Locator.select_option(&1, options, timeout: timeout(opts))
    input(conn, css_selector || "select", label, opts, fun)
  end

  @doc false
  def check(conn, css_selector \\ nil, label, opts) do
    opts = NimbleOptions.validate!(opts, @exact_opts_schema)
    fun = &Locator.check(&1, timeout: timeout(opts))
    input(conn, css_selector || "input[type='checkbox']", label, opts, fun)
  end

  @doc false
  def uncheck(conn, css_selector \\ nil, label, opts) do
    opts = NimbleOptions.validate!(opts, @exact_opts_schema)
    fun = &Locator.uncheck(&1, timeout: timeout(opts))
    input(conn, css_selector || "input[type='checkbox']", label, opts, fun)
  end

  @doc false
  def choose(conn, css_selector \\ nil, label, opts) do
    opts = NimbleOptions.validate!(opts, @exact_opts_schema)
    fun = &Locator.check(&1, timeout: timeout(opts))
    input(conn, css_selector || "input[type='radio']", label, opts, fun)
  end

  @doc false
  def upload(conn, css_selector \\ nil, label, paths, opts) do
    opts = NimbleOptions.validate!(opts, @exact_opts_schema)
    paths = paths |> List.wrap() |> Enum.map(&Path.expand/1)
    fun = &Locator.set_input_files(&1, paths, timeout: timeout(opts))
    input(conn, css_selector || "input[type='file']", label, opts, fun)
  end

  defp input(conn, css_selector, label, opts, fun, input_opts \\ []) do
    selector =
      conn.within
      |> Selector.concat(
        css_selector
        |> Selector.css()
        |> Selector.and(Selector.label(label, opts))
      )
      |> Selector.visible()
      |> Selector.build()

    conn
    |> locator(selector)
    |> fun.()
    |> handle_response(selector)

    # Trigger phx-change for text inputs using phx-debounce="blur". Other
    # controls dispatch their change event as part of the Playwright action.
    if input_opts[:blur], do: conn |> locator(selector) |> Locator.blur(timeout: timeout(opts))

    %{conn | last_input_selector: selector}
  end

  defp ensure_binary(value) when is_binary(value), do: value
  defp ensure_binary(value), do: value |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()

  defp locator(conn, selector), do: Page.locator(conn.page, selector)

  defp handle_response(result, debug_selector) do
    case result do
      {:error, %TimeoutError{} = error} ->
        raise ArgumentError,
              "Could not find element with selector \"#{debug_selector}\"#{timeout_suffix(error)}\n" <>
                more_info(error)

      {:error, %PlaywrightError{message: message} = error} ->
        handle_playwright_error(error, message, debug_selector)

      {:error, error} ->
        raise error

      result ->
        result
    end
  end

  defp handle_playwright_error(error, message, debug_selector) do
    case String.split(message, "strict mode violation: ", parts: 2) do
      [_, short_message] ->
        raise ArgumentError, "Found more than one element matching selector \"#{debug_selector}\":\n#{short_message}"

      _ ->
        if not (message =~ "Clicking the checkbox did not change its state"), do: raise(error)
    end
  end

  defp timeout_suffix(error) do
    case Regex.scan(~r/Timeout (\d+)ms exceeded./, error.message) do
      [[_, timeout]] -> " within #{String.to_integer(timeout)}ms"
      _ -> ""
    end
  end

  defp more_info(%{log: [_ | _] = log}), do: "Playwright log:\n" <> Enum.join(log, "\n")
  defp more_info(error), do: Exception.message(error)

  @doc false
  def submit(conn) do
    conn
    |> locator(conn.last_input_selector)
    |> Locator.evaluate(
      """
      element => {
        const form = element.form;

        if (!form) {
          throw new Error("Last interacted element is not associated with a form");
        }

        const submitter = form.querySelector(
          'button:not([type]):not(:disabled), button[type="submit"]:not(:disabled), input[type="submit"]:not(:disabled), input[type="image"]:not(:disabled)'
        );

        form.requestSubmit(submitter || undefined);
      }
      """,
      nil,
      timeout: timeout()
    )
    |> case do
      {:ok, _} ->
        conn

      {:error, error} = result ->
        if element_not_resolved?(error), do: handle_response(result, conn.last_input_selector)

        raise ExUnit.AssertionError,
          message: "Could not submit form for selector \"#{conn.last_input_selector}\":\n#{more_info(error)}"
    end
  end

  defp element_not_resolved?(%TimeoutError{}), do: true
  defp element_not_resolved?(%PlaywrightError{message: message}), do: message =~ "strict mode violation: "
  defp element_not_resolved?(_error), do: false

  @doc false
  def open_browser(conn, open_fun \\ &OpenBrowser.open_with_system_cmd/1) do
    path = Path.join([System.tmp_dir!(), "phx-test#{System.unique_integer([:monotonic])}.html"])

    # Await any pending navigation
    Process.sleep(100)
    raw_html = bounded!(timeout(), "page.content", fn -> Page.content(conn.page) end)

    fixed_html =
      raw_html
      |> PhoenixTest.Html.parse_document()
      |> PhoenixTest.Html.postwalk(&OpenBrowser.prefix_static_paths(&1, @endpoint))
      |> PhoenixTest.Html.raw()

    File.write!(path, fixed_html)

    open_fun.(path)

    conn
  end

  @evaluate_opts_schema [
    timeout: @timeout_opt,
    arg: [
      type: :any,
      default: nil,
      doc: "Optional argument to pass to the function."
    ]
  ]

  @doc group: "Debugging & escape hatches"
  @doc """
  Evaluates a JavaScript expression in the page context.

  When a callback function is given, it receives the JavaScript result. This
  is useful for assertions or side effects without breaking the pipe chain.
  JavaScript `null` is received as `:null` and `undefined` as `nil`, also when
  nested in objects and arrays.

  Evaluation can't be interrupted, so `:timeout` only limits how long to wait for
  the result, and at least one second is always allowed.

  ## Options
  #{NimbleOptions.docs(@evaluate_opts_schema)}

  ## Examples
      conn
      |> evaluate("window.scrollTo(0, document.body.scrollHeight)")

      conn
      |> evaluate("selectors => selectors.forEach(s => document.querySelector(s).remove())", arg: ["h1"])

      conn
      |> evaluate("document.title", & assert &1 =~ "Dashboard")
  """
  @spec evaluate(t(), String.t()) :: t()
  def evaluate(conn, expression), do: evaluate(conn, expression, [], & &1)

  @doc group: "Debugging & escape hatches"
  @doc "See `evaluate/2`."
  @spec evaluate(t(), String.t(), [unquote(NimbleOptions.option_typespec(@evaluate_opts_schema))] | (any() -> any())) ::
          t()
  def evaluate(conn, expression, fun) when is_function(fun, 1), do: evaluate(conn, expression, [], fun)
  def evaluate(conn, expression, opts) when is_list(opts), do: evaluate(conn, expression, opts, & &1)

  @doc group: "Debugging & escape hatches"
  @doc "See `evaluate/2`."
  @spec evaluate(t(), String.t(), [unquote(NimbleOptions.option_typespec(@evaluate_opts_schema))], (any() -> any())) ::
          t()
  def evaluate(conn, expression, opts, fun) when is_list(opts) and is_function(fun, 1) do
    opts = NimbleOptions.validate!(opts, @evaluate_opts_schema)

    tap(conn, fn conn ->
      case evaluate_within(conn, expression, opts[:arg], timeout(opts)) do
        {:ok, value} ->
          fun.(value)

        {:error, error} ->
          raise ExUnit.AssertionError,
            message: "JavaScript evaluation failed: #{inspect(expression)}\n\n#{inspect(error)}"
      end
    end)
  end

  @doc group: "Debugging & escape hatches"
  @doc """
  See `PhoenixTest.unwrap/2`.

  Invokes `fun` with the Playwright
  [`BrowserContext`](`PlaywrightEx.BrowserContext`),
  [`Page`](`PlaywrightEx.Page`) and
  [`Frame`](`PlaywrightEx.Frame`).

  ## Examples
      |> unwrap(fn %{page: page} -> PlaywrightEx.Page.bring_to_front!(page) end)
  """
  @spec unwrap(t(), (%{context: any(), page: any(), frame: any()} -> any())) :: t()
  def unwrap(conn, fun) do
    tap(conn, &fun.(%{context: &1.context, page: &1.page, frame: Page.main_frame(&1.page)}))
  end

  @doc false
  def current_path(conn) do
    uri = conn.page |> Page.url() |> URI.parse()

    if uri.query in [nil, ""], do: uri.path, else: "#{uri.path}?#{uri.query}"
  end

  # `Page.evaluate/3` has no timeout, so it is bounded here.
  defp evaluate_within(conn, expression, arg, timeout) do
    bounded(timeout, "page.evaluate", fn -> Page.evaluate(conn.page, expression, arg) end)
  end

  # For calls that take no timeout. `fun` must not raise: the task is linked to the caller.
  defp bounded!(timeout, title, fun) do
    case bounded(timeout, title, fun) do
      :ok -> :ok
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  defp bounded(timeout, title, fun) do
    case Browser.within(timeout, fun) do
      {:ok, result} -> result
      :timeout -> {:error, %TimeoutError{message: "#{title}: Timeout #{Config.client_timeout(timeout)}ms exceeded."}}
    end
  end

  defp timeout, do: Config.driver_timeout(Config.global(:timeout))
  defp timeout(opts), do: opts |> Keyword.get(:timeout, Config.global(:timeout)) |> Config.driver_timeout()
  defp ensure_timeout(opts), do: Keyword.put(opts, :timeout, timeout(opts))
end

defimpl PhoenixTest.Driver, for: PhoenixTest.Playwright do
  alias PhoenixTest.Playwright

  defdelegate visit(conn, path), to: Playwright
  defdelegate reload_page(conn), to: Playwright
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

  defdelegate assert_download(conn, filename_or_fun), to: Playwright

  defdelegate assert_path(conn, path), to: Playwright
  defdelegate assert_path(conn, path, opts), to: Playwright
  defdelegate refute_path(conn, path), to: Playwright
  defdelegate refute_path(conn, path, opts), to: Playwright
end
