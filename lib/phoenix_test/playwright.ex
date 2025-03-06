defmodule PhoenixTest.Playwright do
  @moduledoc ~S"""
  Run feature tests in an actual browser, using [PhoenixTest](https://hexdocs.pm/phoenix_test) and [Playwright](https://playwright.dev/).

  ```elixir
  defmodule Features.RegisterTest do
    use PhoenixTest.Playwright.Case,
      async: true,
      parameterize: [                      # run in multiple browsers in parallel
        %{browser: :chromium},
        %{browser: :firefox}
      ],
      headless: false,                     # show browser window
      slow_mo: :timer.seconds(1)           # add delay between interactions

    @tag trace: :open                      # replay in interactive viewer
    test "register", %{conn: conn} do
      conn
      |> visit(~p"/")
      |> click_link("Register")

      |> fill_in("Email", with: "f@ftes.de")
      |> click_button("Create an account")

      |> assert_has(".text-rose-600", text: "required")
      |> screenshot("error.png", full_page: true)
    end
  end
  ```

  Please [get in touch](https://ftes.de) with feedback of any shape and size.

  Enjoy! Freddy.


  ## Getting started
  1. Add dependency
    ```elixir
    # mix.exs
    {:phoenix_test_playwright, "~> 0.4", only: :test, runtime: false}
    ```

  2. Install playwright and browser
    ```
    npm --prefix assets i -D playwright
    npm --prefix assets exec playwright install chromium --with-deps
    ```

  3. Config
    ```elixir
    # config/test.exs
    config :phoenix_test, otp_app: :your_app
    config :your_app, YourAppWeb.Endpoint, server: true
    ```

  4. Runtime config
    ```elixir
    # test/test_helpers.exs
    Application.put_env(:phoenix_test, :base_url, YourAppWeb.Endpoint.url()
    ```

  5. Use in test
    ```elixir
    defmodule MyTest do
      use PhoenixTest.Playwright.Case, async: true

      # `conn` isn't a `Plug.Conn` but a Playwright session.
      # We use the name `conn` anyway so you can easily switch `PhoenixTest` drivers.
      test "in browser", %{conn: conn} do
        conn
        |> visit(~p"/")
        |> unwrap(&Frame.evaluate(&1.frame_id, "console.log('Hey')"))
    ```

  > #### Reference project {: .neutral}
  >
  > [github.com/ftes/phoenix_test_playwright_example](https://github.com/ftes/phoenix_test_playwright_example)
  >
  > The last commit adds a feature test for the `phx gen.auth` registration page
  > and runs it in CI (Github Actions).


  ## Configuration

  ```elixir
  # config/test.ex
  config :phoenix_test,
    otp_app: :your_app,
    playwright: [
      browser: :chromium,
      headless: System.get_env("PW_HEADLESS", "true") in ~w(t true),
      js_logger: false,
      screenshot: System.get_env("PW_SCREENSHOT", "false") in ~w(t true),
      trace: System.get_env("PW_TRACE", "false") in ~w(t true),
    ]
  ```

  See `PhoenixTest.Playwright.Config` for more details.

  You can override some options in your test:

  ```elixir
  defmodule DebuggingFeatureTest do
    use PhoenixTest.Playwright.Case,
      async: true,
      # Show browser and pause 1 second between every interaction
      headless: false,
      slow_mo: :timer.seconds(1)
  ```


  ## Traces
  Playwright traces record a full browser history, including 'user' interaction, browser console, network transfers etc.
  Traces can be explored in an interactive viewer for debugging purposes.

  ### Manually
  ```elixir
  @tag trace: :open
  test "record a trace and open it automatically in the viewer" do
  ```

  ### Automatically for failed tests in CI
  ```elixir
  # config/test.exs
  config :phoenix_test, playwright: [trace: System.get_env("PW_TRACE", "false") in ~w(t true)]
  ```

  ```yaml
  # .github/workflows/elixir.yml
  run: "mix test || if [[ $? = 2 ]]; then PW_TRACE=true mix test --failed; else false; fi"
  ```


  ## Screenshots
  ### Manually
  ```elixir
  |> visit(~p"/")
  |> screenshot("home.png")    # captures entire page by default, not just viewport
  ```

  ### Automatically for failed tests in CI
  ```elixir
  # config/test.exs
  config :phoenix_test, playwright: [screenshot: System.get_env("PW_SCREENSHOT", "false") in ~w(t true)]
  ```

  ```yaml
  # .github/workflows/elixir.yml
  run: "mix test || if [[ $? = 2 ]]; then PW_SCREENSHOT=true mix test --failed; else false; fi"
  ```


  ## Common problems
  ### Test failure in CI (timeout)
  - Limit concurrency: `mix test --max-cases 1` for GitHub CI shared runners
  - Increase timemout: `config :phoenix_test, playwright: [timeout: :timer.seconds(4)]`
  - More compute power: e.g. `x64 8-core` [GitHub runner](https://docs.github.com/en/enterprise-cloud@latest/actions/using-github-hosted-runners/using-larger-runners/about-larger-runners#machine-sizes-for-larger-runners)

  ### LiveView not connected
  ```elixir
  |> visit(~p"/")
  |> assert_has("body .phx-connected")
  # now continue, playwright has waited for LiveView to connect
  ```

  ### LiveComponent not connected
  ```html
  <div id="my-component" data-connected={connected?(@socket)}`>
  ```

  ```elixir
  |> visit(~p"/")
  |> assert_has("#my-component[data-connected]")
  # now continue, playwright has waited for LiveComponent to connect
  ```


  ## Ecto SQL.Sandbox
  ```elixir
  defmodule MyTest do
    use PhoenixTest.Playwright.Case, async: true
  ```

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

  ```elixir
  def assert_a11y(session) do
    A11yAudit.Assertions.assert_no_violations(fn ->
      Frame.evaluate(session.frame_id, A11yAudit.JS.axe_core())

      session.frame_id
      |> Frame.evaluate("axe.run().then(res => JSON.stringify(res))")
      |> JSON.decode!()
      |> A11yAudit.Results.from_json()
    end)

    session
  end

  def assert_download(session, name, contains: content) do
    assert_receive({:playwright, %{method: :download} = download_msg}, 2000)
    artifact_guid = download_msg.params.artifact.guid
    assert_receive({:playwright, %{method: :__create__, params: %{guid: ^artifact_guid}} = artifact_msg}, 2000)
    download_path = artifact_msg.params.initializer.absolute_path
    wait_for_file(download_path)

    assert download_msg.params.suggested_filename =~ name
    assert File.read!(download_path) =~ content

    session
  end

  def assert_has_value(session, label, value, opts \\ []) do
    opts = Keyword.validate!(opts, exact: true)

    assert_found(session,
      selector: Selector.label(label, opts),
      expression: "to.have.value",
      expectedText: [%{string: value}]
    )
  end

  def assert_has_selected(session, label, value, opts \\ []) do
    opts = Keyword.validate!(opts, exact: true)

    assert_found(session,
      selector: label |> Selector.label(opts) |> Selector.concat("option[selected]"),
      expression: "to.have.text",
      expectedText: [%{string: value}]
    )
  end

  def assert_is_chosen(session, label, opts \\ []) do
    opts = Keyword.validate!(opts, exact: true)

    assert_found(session,
      selector: Selector.label(label, opts),
      expression: "to.have.attribute",
      expressionArg: "checked"
    )
  end

  def assert_is_editable(session, label, opts \\ []) do
    opts = Keyword.validate!(opts, exact: true)

    assert_found(session,
      selector: Selector.label(label, opts),
      expression: "to.be.editable"
    )
  end

  def refute_is_editable(session, label, opts \\ []) do
    opts = Keyword.validate!(opts, exact: true)

    assert_found(
      session,
      [
        selector: Selector.label(label, opts),
        expression: "to.be.editable"
      ],
      is_not: true
    )
  end

  def assert_found(session, params, opts \\ []) do
    is_not = Keyword.get(opts, :is_not, false)
    params = Enum.into(params, %{is_not: is_not})

    unwrap(session, fn frame_id ->
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
  ```
  """

  import ExUnit.Assertions

  alias PhoenixTest.OpenBrowser
  alias PhoenixTest.Playwright.Config
  alias PhoenixTest.Playwright.Connection
  alias PhoenixTest.Playwright.Frame
  alias PhoenixTest.Playwright.Page
  alias PhoenixTest.Playwright.Selector

  require Logger

  defstruct [:context_id, :page_id, :frame_id, :last_input_selector, within: :none]

  @opaque t :: %__MODULE__{}
  @type css_selector :: String.t()
  @type playwright_selector :: String.t()
  @type selector :: playwright_selector() | css_selector()

  @exact_opt_schema [type: :boolean, default: false, doc: "Exact or substring text match."]
  @exact_opts_schema [exact: @exact_opt_schema]

  @endpoint Application.compile_env(:phoenix_test, :endpoint)

  @doc false
  def build(context_id, page_id, frame_id) do
    %__MODULE__{context_id: context_id, page_id: page_id, frame_id: frame_id}
  end

  @doc false
  def retry(fun, backoff_ms \\ [100, 250, 500, timeout()])
  def retry(fun, []), do: fun.()

  def retry(fun, [sleep_ms | backoff_ms]) do
    fun.()
  rescue
    ExUnit.AssertionError ->
      Process.sleep(sleep_ms)
      retry(fun, backoff_ms)
  end

  @doc false
  def visit(session, path) do
    url =
      case path do
        "http://" <> _ -> path
        "https://" <> _ -> path
        _ -> Application.fetch_env!(:phoenix_test, :base_url) <> path
      end

    Frame.goto(session.frame_id, url)
    session
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
  @spec screenshot(t(), String.t(), [unquote(NimbleOptions.option_typespec(@screenshot_opts_schema))]) :: t()
  def screenshot(session, file_path, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @screenshot_opts_schema)

    dir = Config.global(:screenshot_dir)
    File.mkdir_p!(dir)

    path = Path.join(dir, file_path)
    {:ok, binary_img} = Page.screenshot(session.page_id, opts)
    File.write!(path, Base.decode64!(binary_img))

    session
  end

  @type_opts_schema [
    delay: [type: :non_neg_integer, default: 0, doc: "Time to wait between key presses in milliseconds."]
  ]
  @doc """
  Focuses the matching element and simulates user typing.

  In most cases, you should use `PhoenixTest.fill_in/4` instead.

  ## Options
  #{NimbleOptions.docs(@type_opts_schema)}

  ## Examples
      |> type("#id", "some text")
      |> type(Selector.role("heading", "Untitled", exact: true), "New title")
  """
  @spec type(t(), selector(), String.t(), [unquote(NimbleOptions.option_typespec(@type_opts_schema))]) :: t()
  def type(session, selector, text, opts \\ []) when is_binary(text) do
    opts = NimbleOptions.validate!(opts, @type_opts_schema)

    session.frame_id
    |> Frame.type(selector, text, opts)
    |> handle_response(selector)

    session
  end

  @press_opts_schema [
    delay: [type: :non_neg_integer, default: 0, doc: "Time to wait between keydown and keyup in milliseconds."]
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
      |> press(Selector.button("Submit", exact: true), "Enter")
  """
  @spec press(t(), selector(), String.t(), [unquote(NimbleOptions.option_typespec(@press_opts_schema))]) :: t()
  def press(session, selector, key, opts \\ []) when is_binary(key) do
    opts = NimbleOptions.validate!(opts, @press_opts_schema)

    session.frame_id
    |> Frame.press(selector, key, opts)
    |> handle_response(selector)

    session
  end

  def assert_has(session, "title") do
    retry(fn -> assert render_page_title(session) != nil end)
  end

  @doc false
  def assert_has(session, selector), do: assert_has(session, selector, [])

  @doc false
  def assert_has(session, "title", opts) do
    text = Keyword.fetch!(opts, :text)
    exact = Keyword.get(opts, :exact, false)

    if exact do
      retry(fn -> assert render_page_title(session) == text end)
    else
      retry(fn -> assert render_page_title(session) =~ text end)
    end

    session
  end

  @doc false
  def assert_has(session, selector, opts) do
    if !found?(session, selector, opts) do
      flunk("Could not find element #{selector} #{inspect(opts)}")
    end

    session
  end

  @doc false
  def refute_has(session, "title") do
    retry(fn -> assert render_page_title(session) == nil end)
  end

  @doc false
  def refute_has(session, selector), do: refute_has(session, selector, [])

  @doc false
  def refute_has(session, "title", opts) do
    text = Keyword.fetch!(opts, :text)
    exact = Keyword.get(opts, :exact, false)

    if exact do
      retry(fn -> refute render_page_title(session) == text end)
    else
      retry(fn -> refute render_page_title(session) =~ text end)
    end

    session
  end

  @doc false
  def refute_has(session, selector, opts) do
    if found?(session, selector, opts) do
      flunk("Found element #{selector} #{inspect(opts)}")
    end

    session
  end

  defp found?(session, selector, opts) do
    selector =
      session
      |> maybe_within()
      |> Selector.concat(Selector.css(selector))
      |> Selector.concat("visible=true")
      |> Selector.concat(Selector.text(opts[:text], opts))

    if opts[:count] do
      if opts[:at],
        do: raise(ArgumentError, message: "Options `count` and `at` can not be used together.")

      params =
        %{
          expression: "to.have.count",
          expected_number: opts[:count],
          selector: Selector.build(selector),
          timeout: timeout(opts)
        }

      {:ok, found?} = Frame.expect(session.frame_id, params)
      found?
    else
      params =
        %{
          selector: selector |> Selector.concat(Selector.at(opts[:at])) |> Selector.build(),
          timeout: timeout(opts)
        }

      case Frame.wait_for_selector(session.frame_id, params) do
        {:ok, _} -> true
        _ -> false
      end
    end
  end

  @doc false
  def render_page_title(session) do
    case Frame.title(session.frame_id) do
      {:ok, ""} -> nil
      {:ok, title} -> title
    end
  end

  @doc false
  def render_html(session) do
    selector = session |> maybe_within() |> Selector.build()
    {:ok, html} = Frame.inner_html(session.frame_id, selector)
    html
  end

  @doc """
  See `click/4`.
  """
  @spec click(t(), selector()) :: t()
  def click(session, selector) do
    session.frame_id
    |> Frame.click(selector)
    |> handle_response(selector)

    session
  end

  @doc """
  Click an element that is not a link or button.
  Otherwise, use `click_link/4` and `click_button/4`.

  ## Options
  #{NimbleOptions.docs(@exact_opts_schema)}

  ## Examples
      |> click(Selector.menuitem("Edit", exact: true))
      |> click("summary", "(expand)", exact: false)
  """
  @spec click(t(), selector(), String.t(), [unquote(NimbleOptions.option_typespec(@exact_opts_schema))]) :: t()
  def click(session, selector, text, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @exact_opts_schema)

    selector =
      session
      |> maybe_within()
      |> Selector.concat(selector)
      |> Selector.concat(Selector.text(text, opts))

    session.frame_id
    |> Frame.click(selector)
    |> handle_response(selector)

    session
  end

  @doc """
  Like `PhoenixTest.click_link/3`, but allows exact text match.

  ## Options
  #{NimbleOptions.docs(@exact_opts_schema)}
  """
  def click_link(session, selector \\ nil, text, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @exact_opts_schema)

    selector =
      session
      |> maybe_within()
      |> Selector.concat(
        case selector do
          nil -> Selector.link(text, opts)
          css -> css |> Selector.css() |> Selector.concat(Selector.text(text, opts))
        end
      )
      |> Selector.build()

    session.frame_id
    |> Frame.click(selector)
    |> handle_response(selector)

    session
  end

  @doc """
  Like `PhoenixTest.click_button/3`, but allows exact text match.

  ## Options
  #{NimbleOptions.docs(@exact_opts_schema)}
  """
  def click_button(session, selector \\ nil, text, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @exact_opts_schema)

    selector =
      session
      |> maybe_within()
      |> Selector.concat(
        case selector do
          nil -> Selector.button(text, opts)
          css -> css |> Selector.css() |> Selector.concat(Selector.text(text, opts))
        end
      )
      |> Selector.build()

    session.frame_id
    |> Frame.click(selector)
    |> handle_response(selector)

    session
  end

  @doc false
  def within(session, selector, fun) do
    session
    |> Map.put(:within, selector)
    |> fun.()
    |> Map.put(:within, :none)
  end

  @doc false
  def fill_in(session, css_selector \\ nil, label, opts) do
    {value, opts} = Keyword.pop!(opts, :with)
    fun = &Frame.fill(session.frame_id, &1, to_string(value), &2)
    input(session, css_selector, label, opts, fun)
  end

  @doc false
  def select(session, css_selector \\ nil, option_labels, opts) do
    if opts[:exact_option] != true, do: raise("exact_option not implemented")

    {label, opts} = Keyword.pop!(opts, :from)
    options = option_labels |> List.wrap() |> Enum.map(&%{label: &1})
    fun = &Frame.select_option(session.frame_id, &1, options, &2)
    input(session, css_selector, label, opts, fun)
  end

  @doc false
  def check(session, css_selector \\ nil, label, opts) do
    fun = &Frame.check(session.frame_id, &1, &2)
    input(session, css_selector, label, opts, fun)
  end

  @doc false
  def uncheck(session, css_selector \\ nil, label, opts) do
    fun = &Frame.uncheck(session.frame_id, &1, &2)
    input(session, css_selector, label, opts, fun)
  end

  @doc false
  def choose(session, css_selector \\ nil, label, opts) do
    fun = &Frame.check(session.frame_id, &1, &2)
    input(session, css_selector, label, opts, fun)
  end

  @doc false
  def upload(session, css_selector \\ nil, label, paths, opts) do
    paths = paths |> List.wrap() |> Enum.map(&Path.expand/1)
    fun = &Frame.set_input_files(session.frame_id, &1, paths, &2)
    input(session, css_selector, label, opts, fun)
  end

  @doc false
  defp input(session, css_selector, label, opts, fun) do
    selector =
      session
      |> maybe_within()
      |> Selector.concat(
        case css_selector do
          nil -> Selector.label(label, opts)
          css -> css |> Selector.css() |> Selector.and(Selector.label(label, opts))
        end
      )
      |> Selector.build()

    selector
    |> fun.(%{timeout: timeout(opts)})
    |> handle_response(selector)

    %{session | last_input_selector: selector}
  end

  defp maybe_within(session) do
    case session.within do
      :none -> Selector.none()
      selector -> selector
    end
  end

  defp handle_response(result, debug_selector) do
    case result do
      {:error, %{error: %{error: %{name: "TimeoutError"} = pw_error}} = error} ->
        base_error_header = "Could not find element with selector #{debug_selector}"

        playwright_message = pw_error[:message]

        error_header =
          case is_binary(playwright_message) &&
                 Regex.scan(~r/Timeout (\d+)ms exceeded./, playwright_message) do
            [[_, timeout]] -> base_error_header <> " within #{String.to_integer(timeout)}ms"
            _ -> base_error_header
          end

        more_info =
          case error[:log] do
            log when is_list(log) -> "Playwright log:\n" <> Enum.join(log, "\n")
            _ -> inspect(error, pretty: true)
          end

        flunk("#{error_header}\n#{more_info}")

      {:error, %{error: %{error: %{message: "Error: strict mode violation: " <> _ = message}}}} ->
        short_message = String.replace(message, "Error: strict mode violation: ", "")

        flunk("Found more than one element matching selector #{debug_selector}:\n#{short_message}")

      {:error,
       %{
         error: %{
           error: %{name: "Error", message: "Clicking the checkbox did not change its state"}
         }
       }} ->
        :ok

      {:ok, result} ->
        result
    end
  end

  @doc false
  def submit(session) do
    Frame.press(session.frame_id, session.last_input_selector, "Enter")
    session
  end

  @doc false
  def open_browser(session, open_fun \\ &OpenBrowser.open_with_system_cmd/1) do
    # Await any pending navigation
    Process.sleep(100)
    {:ok, html} = Frame.content(session.frame_id)

    fixed_html =
      html
      |> Floki.parse_document!()
      |> Floki.traverse_and_update(&OpenBrowser.prefix_static_paths(&1, @endpoint))
      |> Floki.raw_html()

    path = Path.join([System.tmp_dir!(), "phx-test#{System.unique_integer([:monotonic])}.html"])
    File.write!(path, fixed_html)
    open_fun.(path)

    session
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
  def unwrap(session, fun) do
    fun.(Map.take(session, ~w(context_id page_id frame_id)a))
    session
  end

  @doc false
  def current_path(session) do
    resp =
      session.frame_id
      |> Connection.received()
      |> Enum.find(&match?(%{method: :navigated, params: %{url: _}}, &1))

    if resp == nil, do: raise(ArgumentError, "Could not find current path.")

    uri = URI.parse(resp.params.url)
    [uri.path, uri.query] |> Enum.reject(&is_nil/1) |> Enum.join("?")
  end

  defp timeout(opts \\ []) do
    Keyword.get_lazy(opts, :timeout, fn -> Config.global(:timeout) end)
  end
end

defimpl PhoenixTest.Driver, for: PhoenixTest.Playwright do
  import PhoenixTest.Playwright, only: [retry: 1]

  alias PhoenixTest.Assertions
  alias PhoenixTest.Playwright

  defdelegate visit(session, path), to: Playwright
  defdelegate render_page_title(session), to: Playwright
  defdelegate render_html(session), to: Playwright
  defdelegate within(session, selector, fun), to: Playwright
  defdelegate click_link(session, text), to: Playwright
  defdelegate click_link(session, selector, text), to: Playwright
  defdelegate click_button(session, text), to: Playwright
  defdelegate click_button(session, selector, text), to: Playwright
  defdelegate fill_in(session, label, opts), to: Playwright
  defdelegate fill_in(session, selector, label, opts), to: Playwright
  defdelegate select(session, selector, option, opts), to: Playwright
  defdelegate select(session, option, opts), to: Playwright
  defdelegate check(session, selector, label, opts), to: Playwright
  defdelegate check(session, label, opts), to: Playwright
  defdelegate uncheck(session, selector, label, opts), to: Playwright
  defdelegate uncheck(session, label, opts), to: Playwright
  defdelegate choose(session, selector, label, opts), to: Playwright
  defdelegate choose(session, label, opts), to: Playwright
  defdelegate upload(session, selector, label, path, opts), to: Playwright
  defdelegate upload(session, label, path, opts), to: Playwright
  defdelegate submit(session), to: Playwright
  defdelegate open_browser(session), to: Playwright
  defdelegate open_browser(session, open_fun), to: Playwright
  defdelegate unwrap(session, fun), to: Playwright
  defdelegate current_path(session), to: Playwright

  defdelegate assert_has(session, selector), to: Playwright
  defdelegate assert_has(session, selector, opts), to: Playwright
  defdelegate refute_has(session, selector), to: Playwright
  defdelegate refute_has(session, selector, opts), to: Playwright

  def assert_path(session, path), do: retry(fn -> Assertions.assert_path(session, path) end)
  def assert_path(session, path, opts), do: retry(fn -> Assertions.assert_path(session, path, opts) end)
  def refute_path(session, path), do: retry(fn -> Assertions.refute_path(session, path) end)
  def refute_path(session, path, opts), do: retry(fn -> Assertions.refute_path(session, path, opts) end)
end
