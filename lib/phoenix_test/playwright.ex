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

  P.S. Looking for a standalone Playwright client? See [playwright_ex](https://hexdocs.pm/playwright_ex/).


  ## Getting started
  1. Add dependency
          # mix.exs
          {:phoenix_test_playwright, "~> 0.4", only: :test, runtime: false}

  2. Install playwright and browser
          npm --prefix assets i -D playwright
          npm --prefix assets exec -- playwright install chromium --with-deps

  3. Config
          # config/test.exs
          config :phoenix_test, otp_app: :your_app
          config :your_app, YourAppWeb.Endpoint, server: true

  4. Runtime config
          # test/test_helpers.exs
          {:ok, _} = PhoenixTest.Playwright.Supervisor.start_link()
          Application.put_env(:phoenix_test, :base_url, YourAppWeb.Endpoint.url()

  5. Use in test
          defmodule MyTest do
            use PhoenixTest.Playwright.Case, async: true

            # `conn` isn't a `Plug.Conn` but a Playwright session.
            # We use the name `conn` anyway so you can easily switch `PhoenixTest` drivers.
            test "in browser", %{conn: conn} do
              conn
              |> visit(~p"/")
              |> unwrap(&Frame.evaluate(&1.frame_id, "console.log('Hey')"))

  > #### Reference project {: .neutral}
  >
  > [github.com/ftes/phoenix_test_playwright_example](https://github.com/ftes/phoenix_test_playwright_example)
  >
  > The last commit adds a feature test for the `phx gen.auth` registration page
  > and runs it in CI (Github Actions).


  ## Configuration
      # config/test.ex
      config :phoenix_test,
        otp_app: :your_app,
        playwright: [
          browser_pool: :chromium_pool,
          browser_pools: [
            [id: :chromium_pool, browser: :chromium],
            [id: :firefox_pool, browser: :firefox]
          ],
          js_logger: false,
          browser_launch_timeout: 10_000
        ]

  See `PhoenixTest.Playwright.Config` for more details.

  You can override some options in your test:
      defmodule DebuggingFeatureTest do
        use PhoenixTest.Playwright.Case,
          async: true,
          # Launch new browser for this test suite with custom options below
          browser_pool: :nil,
          # Show browser and pause 1 second between every interaction
          headless: false,
          slow_mo: :timer.seconds(1)


  ## Traces
  Playwright traces record a full browser history, including 'user' interaction, browser console, network transfers etc.
  Traces can be explored in an interactive viewer for debugging purposes.

  ### Manually
      @tag trace: :open
      test "record a trace and open it automatically in the viewer" do

  ### Automatically for failed tests in CI
      # config/test.exs
      config :phoenix_test, playwright: [trace: System.get_env("PW_TRACE", "false") in ~w(t true)]

  ```yaml
  # .github/workflows/elixir.yml
  run: "mix test || if [[ $? = 2 ]]; then PW_TRACE=true mix test --failed; else false; fi"
  ```


  ## Screenshots
  ### Manually
      |> visit(~p"/")
      |> screenshot("home.png")    # captures entire page by default, not just viewport

  ### Automatically for failed tests in CI
      # config/test.exs
      config :phoenix_test, playwright: [screenshot: System.get_env("PW_SCREENSHOT", "false") in ~w(t true)]

  ```yaml
  # .github/workflows/elixir.yml
  run: "mix test || if [[ $? = 2 ]]; then PW_SCREENSHOT=true mix test --failed; else false; fi"
  ```


  ## Emails
  If you want to verify the HTML of sent emails in your feature tests,
  consider using `Plug.Swoosh.MailboxPreview`.
  The iframe used to render the email HTML body makes this slightly tricky:

      |> visit(~p"/dev/mailbox")
      |> click_link("Confirmation instructions")
      |> within("iframe >> internal:control=enter-frame", fn conn ->
        conn
        |> click_link("Confirm account")
        |> click_button("Confirm my account")
        |> assert_has("#flash-info", text: "User confirmed")

  For a full example see [ftes/phoenix_test_playwright_example/tree/phoenix-1.8](https://github.com/ftes/phoenix_test_playwright_example/tree/phoenix-1.8).


  ## Common problems
  ### Test failure in CI (timeout)
  - Limit concurrency: `config :phoenix_test, playwright: [browser_pools: [[size: 1]]]` or `mix test --max-cases 1` for GitHub CI shared runners
  - Increase timemout: `config :phoenix_test, playwright: [timeout: :timer.seconds(4)]`
  - More compute power: e.g. `x64 8-core` [GitHub runner](https://docs.github.com/en/enterprise-cloud@latest/actions/using-github-hosted-runners/using-larger-runners/about-larger-runners#machine-sizes-for-larger-runners)

  ### LiveView not connected
      |> visit(~p"/")
      |> assert_has("body .phx-connected")
      # now continue, playwright has waited for LiveView to connect

  ### LiveComponent not connected
  ```html
  <div id="my-component" data-connected={connected?(@socket)}`>
  ```

      |> visit(~p"/")
      |> assert_has("#my-component[data-connected]")
      # now continue, playwright has waited for LiveComponent to connect


  ## Ecto SQL.Sandbox
      defmodule MyTest do
        use PhoenixTest.Playwright.Case, async: true

  `PhoenixTest.Playwright.Case` automatically takes care of this.
  It passes a user agent referencing your Ecto repos.
  This allows for [concurrent browser tests](https://hexdocs.pm/phoenix_ecto/main.html#concurrent-browser-tests).

  Make sure to follow the advanced set up instructions if necessary:
  - [with LiveViews](https://hexdocs.pm/phoenix_ecto/Phoenix.Ecto.SQL.Sandbox.html#module-acceptance-tests-with-liveviews)
  - [with Channels](https://hexdocs.pm/phoenix_ecto/Phoenix.Ecto.SQL.Sandbox.html#module-acceptance-tests-with-channels)


  ## Missing Playwright features
  This module includes functions that are not part of the PhoenixTest protocol, e.g. `screenshot/3` and `click_link/4`.

  But it does not wrap the entire Playwright API, which is quite large.
  You should be able to add any missing functionality yourself
  using `PhoenixTest.unwrap/2`, [`Frame`](`PhoenixTest.Playwright.Frame`), [`Selector`](`PhoenixTest.Playwright.Selector`),
  and the [Playwright code](https://github.com/microsoft/playwright/blob/main/packages/playwright-core/src/client/frame.ts).

  If you think others might benefit, please [open a PR](https://github.com/ftes/phoenix_test_playwright/pulls).

  Here is some inspiration:
      def choose_styled_radio_with_hidden_input_button(session, label, opts \\ []) do
        opts = Keyword.validate!(opts, exact: true)
        click(Selector.text(label, opts))
      end

      defp assert_a11y(conn) do
        Frame.evaluate(conn.frame_id, A11yAudit.JS.axe_core())
        {:ok, json} = Frame.evaluate(conn.frame_id, "axe.run()")
        results = A11yAudit.Results.from_json(json)
        A11yAudit.Assertions.assert_no_violations(results)

        conn
      end

      # In your test, first call `|> tap(&Connection.subscribe(&1.page_id))`
      def assert_download(conn, name, contains: content) do
        assert_receive({:playwright, %{method: :download} = download_msg}, 2000)
        path = Connection.initializer(download_msg.params.artifact.guid).absolute_path
        wait_for_file(path)

        assert download_msg.params.suggested_filename =~ name
        assert File.read!(path) =~ content

        conn
      end

      def assert_has_selected(conn, label, value, opts \\ []) do
        opts = Keyword.validate!(opts, exact: true)

        assert_found(conn,
          selector: label |> Selector.label(opts) |> Selector.concat("option[selected]"),
          expression: "to.have.text",
          expectedText: [%{string: value}]
        )
      end

      def assert_is_chosen(conn, label, opts \\ []) do
        opts = Keyword.validate!(opts, exact: true)

        assert_found(conn,
          selector: Selector.label(label, opts),
          expression: "to.have.attribute",
          expressionArg: "checked"
        )
      end

      def assert_is_editable(conn, label, opts \\ []) do
        opts = Keyword.validate!(opts, exact: true)

        assert_found(conn,
          selector: Selector.label(label, opts),
          expression: "to.be.editable"
        )
      end

      def refute_is_editable(conn, label, opts \\ []) do
        opts = Keyword.validate!(opts, exact: true)

        assert_found(
          conn,
          [
            selector: Selector.label(label, opts),
            expression: "to.be.editable"
          ],
          is_not: true
        )
      end

      def assert_found(conn, params, opts \\ []) do
        is_not = Keyword.get(opts, :is_not, false)
        params = Enum.into(params, %{is_not: is_not})

        unwrap(conn, fn frame_id ->
          {:ok, found} = Frame.expect(frame_id, params)
          if is_not, do: refute(found), else: assert(found)
        end)
      end

      defp wait_for_file(path, remaining_ms \\ 2000, wait_for_ms \\ 100)
      defp wait_for_file(path, remaining_ms, _) when remaining_ms <= 0, do: flunk("File #{path} does not exist")

      defp wait_for_file(path, remaining_ms, wait_for_ms) do
        if File.exists?(path) do
          :ok
        else
          Process.sleep(wait_for_ms)
          wait_for_file(path, remaining_ms - wait_for_ms, wait_for_ms)
        end
      end

      defp within_iframe(selector \\ "iframe", fun) when is_function(fun, 1) do
        within("#{selector} >> internal:control=enter-frame", fun)
      end
  """

  import ExUnit.Assertions

  alias PhoenixTest.Assertions
  alias PhoenixTest.OpenBrowser
  alias PhoenixTest.Playwright.BrowserContext
  alias PhoenixTest.Playwright.Config
  alias PhoenixTest.Playwright.CookieArgs
  alias PhoenixTest.Playwright.Dialog
  alias PhoenixTest.Playwright.EventListener
  alias PhoenixTest.Playwright.EventRecorder
  alias PhoenixTest.Playwright.Frame
  alias PhoenixTest.Playwright.Page
  alias PhoenixTest.Playwright.Selector

  require Logger

  defstruct [
    :context_id,
    :page_id,
    :frame_id,
    :navigate_recorder_pid,
    :dialog_listener_pid,
    :last_input_selector,
    within: :none
  ]

  @opaque t :: %__MODULE__{}
  @type css_selector :: String.t()
  @type playwright_selector :: String.t()
  @type selector :: playwright_selector() | css_selector()

  @exact_opt_schema [type: :boolean, default: false, doc: "Exact or substring text match."]
  @exact_opts_schema [exact: @exact_opt_schema]

  @endpoint Application.compile_env(:phoenix_test, :endpoint)

  @doc false
  def build(%{context_id: context_id, page_id: page_id, frame_id: frame_id, config: config}) do
    %__MODULE__{
      context_id: context_id,
      page_id: page_id,
      frame_id: frame_id,
      navigate_recorder_pid: start_navigate_recorder(frame_id),
      dialog_listener_pid: start_dialog_listener(page_id, config[:accept_dialogs])
    }
  end

  defp start_navigate_recorder(frame_id) do
    args = %{guid: frame_id, filter: &match?(%{method: :navigated}, &1)}
    ExUnit.Callbacks.start_supervised!({EventRecorder, args}, id: "#{frame_id}-navigate-recorder")
  end

  defp start_dialog_listener(page_id, auto_accept?) do
    filter = &match?(%{method: :__create__, params: %{type: "Dialog"}}, &1)
    callback = &if(auto_accept?, do: {:ok, _} = Dialog.accept(&1.params.guid))
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

  @doc false
  def visit(conn, path) do
    url =
      case path do
        "http://" <> _ -> path
        "https://" <> _ -> path
        _ -> Application.fetch_env!(:phoenix_test, :base_url) <> path
      end

    tap(conn, &({:ok, _} = Frame.goto(&1.frame_id, url)))
  end

  @doc """
  Add cookies to the browser context, using `Plug.Conn.put_resp_cookie/3`

  Note that for signed cookies the signing salt is **not** configurable.
  As such, this function is not appropriate for signed `Plug.Session` cookies.
  For signed session cookies, use `add_session_cookie/3`

  See `PhoenixTest.Playwright.CookieArgs` for the type of the cookie.
  """
  def add_cookies(conn, cookies) do
    cookies = Enum.map(cookies, &CookieArgs.from_cookie/1)
    tap(conn, &({:ok, _} = BrowserContext.add_cookies(&1.context_id, cookies)))
  end

  @doc """
  Removes all cookies from the context
  """
  def clear_cookies(conn, opts \\ []) do
    tap(conn, &({:ok, _} = BrowserContext.clear_cookies(&1.context_id, opts)))
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
    tap(conn, &({:ok, _} = BrowserContext.add_cookies(&1.context_id, [cookie])))
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
    ]
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
    {:ok, binary_img} = Page.screenshot(conn.page_id, opts)
    File.write!(path, Base.decode64!(binary_img))

    conn
  end

  @type_opts_schema [
    delay: [
      type: :non_neg_integer,
      default: 0,
      doc: "Time to wait between key presses in milliseconds."
    ]
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
    opts = NimbleOptions.validate!(opts, @type_opts_schema)

    conn.frame_id
    |> Frame.type(selector, text, opts)
    |> handle_response(selector)

    conn
  end

  @press_opts_schema [
    delay: [
      type: :non_neg_integer,
      default: 0,
      doc: "Time to wait between keydown and keyup in milliseconds."
    ]
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
    opts = NimbleOptions.validate!(opts, @press_opts_schema)

    conn.frame_id
    |> Frame.press(selector, key, opts)
    |> handle_response(selector)

    conn
  end

  @drag_opts_schema [
    to: [
      type_spec: quote(do: selector()),
      type_doc: "`t:selector/0`",
      required: true,
      doc: "The target selector."
    ]
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
  def drag(conn, source_selector, to: target_selector) do
    source_selector = conn |> maybe_within() |> Selector.concat(source_selector)
    target_selector = conn |> maybe_within() |> Selector.concat(target_selector)

    conn.frame_id
    |> Frame.drag_and_drop(source_selector, target_selector)
    |> handle_response(source_selector)

    conn
  end

  def assert_path(conn, path, opts \\ []) do
    if opts[:query_params] do
      retry(fn -> Assertions.assert_path(conn, path, opts) end, timeout(opts))
    else
      retry(fn -> Assertions.assert_path(conn, path) end, timeout(opts))
    end
  end

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
    if not found?(conn, selector, opts), do: flunk("Could not find element #{selector} #{inspect(opts)}")
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
    if found?(conn, selector, opts, is_not: true), do: flunk("Found element #{selector} #{inspect(opts)}")
    conn
  end

  defp has_title?(conn, opts, params \\ []) do
    opts = Keyword.validate!(opts, [:text, exact: false])

    params =
      Enum.into(params, %{
        expression: "to.have.title",
        expected_text: [%{string: Keyword.fetch!(opts, :text), match_substring: not opts[:exact]}],
        timeout: timeout(opts)
      })

    {:ok, matches?} = Frame.expect(conn.frame_id, params)
    matches?
  end

  defp found?(conn, selector, opts, other_params \\ []) do
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
          %{expression: "to.have.count", expected_number: count, selector: Selector.build(selector)}

        _ ->
          selector = Selector.concat(selector, Selector.at(opts[:at] || 0))
          %{expression: "to.be.visible", selector: selector}
      end

    params = Enum.into(params, Enum.into(other_params, %{timeout: timeout(opts)}))
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
          :accept -> Dialog.accept(guid)
          {:accept, prompt_text} -> Dialog.accept(guid, prompt_text: prompt_text)
          :dismiss -> Dialog.dismiss(guid)
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
    case Frame.title(conn.frame_id) do
      {:ok, ""} -> nil
      {:ok, title} -> title
    end
  end

  @doc false
  def render_html(conn) do
    selector = conn |> maybe_within() |> Selector.build()
    {:ok, html} = Frame.inner_html(conn.frame_id, selector)
    html
  end

  @doc """
  See `click/4`.
  """
  @spec click(t(), selector()) :: t()
  def click(conn, selector) do
    conn.frame_id
    |> Frame.click(selector)
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
    |> Frame.click(selector)
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
    |> Frame.click(selector)
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
    |> Frame.click(selector)
    |> handle_response(selector)

    conn
  end

  @doc false
  def fill_in(conn, css_selector \\ nil, label, opts) do
    {value, opts} = Keyword.pop!(opts, :with)
    fun = &Frame.fill(conn.frame_id, &1, to_string(value), &2)
    input(conn, css_selector, label, opts, fun)
  end

  @doc false
  def select(conn, css_selector \\ nil, option_labels, opts) do
    if opts[:exact_option] != true, do: raise("exact_option not implemented")

    {label, opts} = Keyword.pop!(opts, :from)
    options = option_labels |> List.wrap() |> Enum.map(&%{label: &1})
    fun = &Frame.select_option(conn.frame_id, &1, options, &2)
    input(conn, css_selector, label, opts, fun)
  end

  @doc false
  def check(conn, css_selector \\ nil, label, opts) do
    fun = &Frame.check(conn.frame_id, &1, &2)
    input(conn, css_selector, label, opts, fun)
  end

  @doc false
  def uncheck(conn, css_selector \\ nil, label, opts) do
    fun = &Frame.uncheck(conn.frame_id, &1, &2)
    input(conn, css_selector, label, opts, fun)
  end

  @doc false
  def choose(conn, css_selector \\ nil, label, opts) do
    fun = &Frame.check(conn.frame_id, &1, &2)
    input(conn, css_selector, label, opts, fun)
  end

  @doc false
  def upload(conn, css_selector \\ nil, label, paths, opts) do
    paths = paths |> List.wrap() |> Enum.map(&Path.expand/1)
    fun = &Frame.set_input_files(conn.frame_id, &1, paths, &2)
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
    |> fun.(%{timeout: timeout(opts)})
    |> handle_response(selector)

    # trigger phx-change if phx-debounce="blur"
    Frame.blur(conn.frame_id, selector)

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
      {:error, %{error: %{error: %{name: "TimeoutError"}}} = error} ->
        flunk(
          "Could not find element with selector #{debug_selector}#{timeout_suffix(error)}\n" <>
            more_info(error)
        )

      {:error, %{error: %{error: %{message: "Error: strict mode violation: " <> _ = message}}}} ->
        short_message = String.replace(message, "Error: strict mode violation: ", "")

        flunk("Found more than one element matching selector #{debug_selector}:\n#{short_message}")

      {:error, %{error: %{error: %{name: "Error", message: ^checkbox_msg}}}} ->
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
    Frame.press(conn.frame_id, conn.last_input_selector, "Enter")
    conn
  end

  @doc false
  def open_browser(conn, open_fun \\ &OpenBrowser.open_with_system_cmd/1) do
    path = Path.join([System.tmp_dir!(), "phx-test#{System.unique_integer([:monotonic])}.html"])

    # Await any pending navigation
    Process.sleep(100)
    {:ok, raw_html} = Frame.content(conn.frame_id)

    fixed_html =
      raw_html
      |> PhoenixTest.Html.parse_document()
      |> PhoenixTest.Html.postwalk(&OpenBrowser.prefix_static_paths(&1, @endpoint))
      |> PhoenixTest.Html.raw()

    File.write!(path, fixed_html)

    open_fun.(path)

    conn
  end

  @doc """
  See `PhoenixTest.unwrap/2`.

  Invokes `fun` with various Playwright IDs.
  These can be used to interact with the Playwright
  [`BrowserContext`](`PhoenixTest.Playwright.BrowserContext`),
  [`Page`](`PhoenixTest.Playwright.Page`) and
  [`Frame`](`PhoenixTest.Playwright.Frame`).

  ## Examples
      |> unwrap(&Frame.evaluate(&1.frame_id, "console.log('Hey')"))
  """
  @spec unwrap(t(), (%{context_id: any(), page_id: any(), frame_id: any()} -> any())) :: t()
  def unwrap(conn, fun) do
    tap(conn, &fun.(Map.take(&1, ~w(context_id page_id frame_id)a)))
  end

  @doc false
  def current_path(conn) do
    [event | _] = EventRecorder.events(conn.navigate_recorder_pid)
    uri = URI.parse(event.params.url)
    [uri.path, uri.query] |> Enum.reject(&is_nil/1) |> Enum.join("?")
  end

  defp timeout(opts) do
    Keyword.get_lazy(opts, :timeout, fn -> Config.global(:timeout) end)
  end
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
