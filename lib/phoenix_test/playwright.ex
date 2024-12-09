defmodule PhoenixTest.Playwright do
  @moduledoc """
  > #### Warning {: .warning}
  >
  > This driver is experimental.
  > If you don't need browser based tests, see `m:PhoenixTest#module-usage` on regular usage.

  Execute PhoenixTest cases in an actual browser via [Playwright](https://playwright.dev/).


  ## Setup


  1. Add to `mix.exs` deps: `{:phoenix_test_playwright, "~> 0.1", only: :test, runtime: false}`
  2. Install Playwright: `npm --prefix assets i -D playwright`
  3. Install browsers: `npm --prefix assets exec playwright install --with-deps`
  4. Add to `config/test.exs`: `config :phoenix_test, otp_app: :your_app, playwright: [cli: "assets/node_modules/playwright/cli.js"]`
  5. Add to `test/test_helpers.exs`: `Application.put_env(:phoenix_test, :base_url, YourAppWeb.Endpoint.url())`


  ## Usage
  ```elixir
  defmodule MyFeatureTest do
    use PhoenixTest.Case, async: true
    @moduletag :playwright

    test "heading", %{conn: conn} do
      conn
      |> visit("/")
      |> assert_has("h1", text: "Heading")
    end
  end
  ```

  As shown above, you can use `m:ExUnit.Case#module-parameterized-tests` parameterized tests
  to run tests concurrently in different browsers.


  ## Known limitations and inconsistencies

  - `PhoenixTest.select/4` option `exact_option` is not supported
  - Playwright driver is less strict than `Live` and `Static` drivers. It does not raise errors
    - when visiting a page that returns a `404` status
    - when interactive elements such as forms and buttons are missing essential attributes (`phx-click`, `phx-submit`, `action`)
  - A few small bugs

  See tests tagged with [`@tag playwright: false`](https://github.com/search?q=repo%3Agermsvel%2Fphoenix_test%20%22%40tag%20playwright%3A%20false%22&type=code)
  for details.


  ## Configuration

  In `config/test.exs`:

  ```elixir
  config :phoenix_test,
    playwright: [
      cli: "assets/node_modules/playwright/cli.js",
      browser: [browser: :chromium, headless: System.get_env("PLAYWRIGHT_HEADLESS", "t") in ~w(t true)],
      trace: System.get_env("PLAYWRIGHT_TRACE", "false") in ~w(t true),
      trace_dir: "tmp"
    ],
    timeout_ms: 2000
  ```

  ## Ecto SQL.Sandbox

  `PhoenixTest.Case` automatically takes care of this.
  It passes a user agent referencing your Ecto repos.
  This allows for [concurrent browser tests](https://hexdocs.pm/phoenix_ecto/main.html#concurrent-browser-tests).

  ```elixir
  defmodule MyTest do
    use PhoenixTest.Case, async: true
  ```
  """

  alias PhoenixTest.Assertions
  alias PhoenixTest.Element.Button
  alias PhoenixTest.Element.Link
  alias PhoenixTest.OpenBrowser
  alias PhoenixTest.Playwright.Connection
  alias PhoenixTest.Playwright.Frame
  alias PhoenixTest.Playwright.Selector
  alias PhoenixTest.Query

  require Logger

  defstruct [:page_id, :frame_id, :last_input_selector, within: :none]

  @endpoint Application.compile_env(:phoenix_test, :endpoint)
  @default_timeout_ms 2000

  def build(page_id, frame_id) do
    %__MODULE__{page_id: page_id, frame_id: frame_id}
  end

  def retry(fun, backoff_ms \\ [100, 250, 500, timeout()])
  def retry(fun, []), do: fun.()

  def retry(fun, [sleep_ms | backoff_ms]) do
    fun.()
  rescue
    ExUnit.AssertionError ->
      Process.sleep(sleep_ms)
      retry(fun, backoff_ms)
  end

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

  def assert_has(session, "title") do
    retry(fn -> Assertions.assert_has(session, "title") end)
  end

  def assert_has(session, selector), do: assert_has(session, selector, [])

  def assert_has(session, "title", opts) do
    retry(fn -> Assertions.assert_has(session, "title", opts) end)
  end

  def assert_has(session, selector, opts) do
    if !found?(session, selector, opts) do
      Assertions.assert_has(session, selector, opts) ||
        raise(fallback_error("Could not find element."))
    end

    session
  end

  def refute_has(session, "title") do
    retry(fn -> Assertions.refute_has(session, "title") end)
  end

  def refute_has(session, selector), do: refute_has(session, selector, [])

  def refute_has(session, "title", opts) do
    retry(fn -> Assertions.refute_has(session, "title", opts) end)
  end

  def refute_has(session, selector, opts) do
    if found?(session, selector, opts) do
      Assertions.refute_has(session, selector, opts) || raise(fallback_error("Found element."))
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
          expectedNumber: opts[:count],
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

  def render_page_title(session) do
    case Frame.title(session.frame_id) do
      {:ok, ""} -> nil
      {:ok, title} -> title
    end
  end

  def render_html(session) do
    selector = session |> maybe_within() |> Selector.build()
    {:ok, html} = Frame.inner_html(session.frame_id, selector)
    html
  end

  def click(session, selector) do
    session.frame_id
    |> Frame.click(selector)
    |> handle_response(fn -> :no_error end)

    session
  end

  def click(session, selector, text, opts \\ []) do
    opts = Keyword.validate!(opts, exact: false)

    selector = Selector.concat(selector, Selector.text(text, opts))

    session.frame_id
    |> Frame.click(selector)
    |> handle_response(fn -> :no_error end)

    session
  end

  def click_link(session, orig_selector, text, opts \\ []) do
    opts = Keyword.validate!(opts, exact: false)

    selector =
      session
      |> maybe_within()
      |> Selector.concat(
        case orig_selector do
          :by_role -> Selector.link(text, opts)
          css -> css |> Selector.css() |> Selector.concat(Selector.text(text, opts))
        end
      )
      |> Selector.build()

    session.frame_id
    |> Frame.click(selector)
    |> handle_response(fn -> Link.find!(render_html(session), to_string(orig_selector), text) end)

    session
  end

  def click_button(session, orig_selector, text, opts \\ []) do
    opts = Keyword.validate!(opts, exact: false)

    selector =
      session
      |> maybe_within()
      |> Selector.concat(
        case orig_selector do
          :by_role -> Selector.button(text, opts)
          css -> css |> Selector.css() |> Selector.concat(Selector.text(text, opts))
        end
      )
      |> Selector.build()

    session.frame_id
    |> Frame.click(selector)
    |> handle_response(fn ->
      Button.find!(render_html(session), to_string(orig_selector), text)
    end)

    session
  end

  def within(session, selector, fun) do
    session
    |> Map.put(:within, selector)
    |> fun.()
    |> Map.put(:within, :none)
  end

  def fill_in(session, input_selector, label, opts) do
    {value, opts} = Keyword.pop!(opts, :with)
    fun = &Frame.fill(session.frame_id, &1, to_string(value), &2)
    input(session, input_selector, label, opts, fun)
  end

  def select(session, input_selector, option_labels, opts) do
    if opts[:exact_option] != true, do: raise("exact_option not implemented")

    {label, opts} = Keyword.pop!(opts, :from)
    options = option_labels |> List.wrap() |> Enum.map(&%{label: &1})
    fun = &Frame.select_option(session.frame_id, &1, options, &2)
    input(session, input_selector, label, opts, fun)
  end

  def check(session, input_selector, label, opts) do
    fun = &Frame.check(session.frame_id, &1, &2)
    input(session, input_selector, label, opts, fun)
  end

  def uncheck(session, input_selector, label, opts) do
    fun = &Frame.uncheck(session.frame_id, &1, &2)
    input(session, input_selector, label, opts, fun)
  end

  def choose(session, input_selector, label, opts) do
    fun = &Frame.check(session.frame_id, &1, &2)
    input(session, input_selector, label, opts, fun)
  end

  def upload(session, input_selector, label, paths, opts) do
    paths = paths |> List.wrap() |> Enum.map(&Path.expand/1)
    fun = &Frame.set_input_files(session.frame_id, &1, paths, &2)
    input(session, input_selector, label, opts, fun)
  end

  defp input(session, input_selector, label, opts, fun) do
    selector =
      session
      |> maybe_within()
      |> Selector.concat(Selector.css(input_selector))
      |> Selector.and(Selector.label(label, opts))
      |> Selector.build()

    selector
    |> fun.(%{timeout: timeout(opts)})
    |> handle_response(fn ->
      Query.find_by_label!(render_html(session), input_selector, label, opts)
    end)

    %{session | last_input_selector: selector}
  end

  defp maybe_within(session) do
    case session.within do
      :none -> Selector.none()
      selector -> Selector.css(selector)
    end
  end

  defp handle_response(result, error_fun) do
    case result do
      {:error, %{error: %{error: %{name: "TimeoutError"}}} = error} ->
        Logger.error(error)
        error_fun.() || raise(fallback_error("Could not find element."))

      {:error,
       %{error: %{error: %{name: "Error", message: "Error: strict mode violation" <> _}}} = error} ->
        Logger.error(error)
        error_fun.() || raise(fallback_error("Found more than one element."))

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

  defp fallback_error(msg) do
    raise ExUnit.AssertionError, message: msg
  end

  def submit(session) do
    Frame.press(session.frame_id, session.last_input_selector, "Enter")
    session
  end

  def open_browser(session, open_fun \\ &OpenBrowser.open_with_system_cmd/1) do
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

  def unwrap(session, fun) do
    fun.(session.frame_id)
    session
  end

  def current_path(session) do
    resp =
      session.frame_id
      |> Connection.received()
      |> Enum.find(&match?(%{method: "navigated", params: %{url: _}}, &1))

    if resp == nil, do: raise(ArgumentError, "Could not find current path.")

    uri = URI.parse(resp.params.url)
    [uri.path, uri.query] |> Enum.reject(&is_nil/1) |> Enum.join("?")
  end

  defp timeout(opts \\ []) do
    default = Application.get_env(:phoenix_test, :timeout_ms, @default_timeout_ms)
    Keyword.get(opts, :timeout, default)
  end
end

defimpl PhoenixTest.Driver, for: PhoenixTest.Playwright do
  alias PhoenixTest.Assertions
  alias PhoenixTest.Playwright

  defdelegate visit(session, path), to: Playwright
  defdelegate render_page_title(session), to: Playwright
  defdelegate render_html(session), to: Playwright
  defdelegate click_link(session, selector, text), to: Playwright
  defdelegate click_button(session, selector, text), to: Playwright
  defdelegate within(session, selector, fun), to: Playwright
  defdelegate fill_in(session, input_selector, label, opts), to: Playwright
  defdelegate select(session, input_selector, option, opts), to: Playwright
  defdelegate check(session, input_selector, label, opts), to: Playwright
  defdelegate uncheck(session, input_selector, label, opts), to: Playwright
  defdelegate choose(session, input_selector, label, opts), to: Playwright
  defdelegate upload(session, input_selector, label, path, opts), to: Playwright
  defdelegate submit(session), to: Playwright
  defdelegate open_browser(session), to: Playwright
  defdelegate open_browser(session, open_fun), to: Playwright
  defdelegate unwrap(session, fun), to: Playwright
  defdelegate current_path(session), to: Playwright

  defdelegate assert_has(session, selector), to: Playwright
  defdelegate assert_has(session, selector, opts), to: Playwright
  defdelegate refute_has(session, selector), to: Playwright
  defdelegate refute_has(session, selector, opts), to: Playwright

  def assert_path(session, path),
    do: Playwright.retry(fn -> Assertions.assert_path(session, path) end)

  def assert_path(session, path, opts),
    do: Playwright.retry(fn -> Assertions.assert_path(session, path, opts) end)

  def refute_path(session, path),
    do: Playwright.retry(fn -> Assertions.refute_path(session, path) end)

  def refute_path(session, path, opts),
    do: Playwright.retry(fn -> Assertions.refute_path(session, path, opts) end)
end
