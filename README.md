[![Hex.pm Version](https://img.shields.io/hexpm/v/phoenix_test_playwright)](https://hex.pm/packages/phoenix_test_playwright)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/phoenix_test_playwright/)
[![License](https://img.shields.io/hexpm/l/phoenix_test_playwright.svg)](https://github.com/ftes/phoenix_test_playwright/blob/main/LICENSE.md)
[![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/ftes/phoenix_test_playwright/elixir.yml)](https://github.com/ftes/phoenix_test_playwright/actions)

# PhoenixTestPlaywright

Execute [PhoenixTest](https://hexdocs.pm/phoenix_test) cases in an actual browser via [Playwright](https://playwright.dev/).

```elixir
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
```

Please [get in touch](https://ftes.de) with feedback of any shape and size.

Enjoy! Freddy.

P.S. Looking for a standalone Playwright client? See [PlaywrightEx](https://github.com/ftes/playwright_ex).

## Getting started

1. Add dependency

    ```elixir
    # mix.exs
    {:phoenix_test_playwright, "~> 0.12", only: :test, runtime: false}
    ```

2. Install playwright and browser

    ```sh
    npm --prefix assets i -D playwright
    npx --prefix assets playwright install chromium --with-deps
    ```

3. Config

    ```elixir
    # config/test.exs
    config :phoenix_test, otp_app: :your_app
    config :your_app, YourAppWeb.Endpoint, server: true
    ```

4. Runtime config

    ```elixir
    # test/test_helper.exs
    {:ok, _} = PhoenixTest.Playwright.Supervisor.start_link()
    Application.put_env(:phoenix_test, :base_url, YourAppWeb.Endpoint.url())
    ```

5. Use in test

    ```elixir
    defmodule MyTest do
      use PhoenixTest.Playwright.Case

      # `conn` isn't a `Plug.Conn` but a Playwright session.
      # We use the name `conn` anyway so you can easily switch `PhoenixTest` drivers.
      test "in browser", %{conn: conn} do
        conn
        |> visit(~p"/")
        |> evaluate("console.log('Hey')")
      end
    end
    ```

6. (Optional) Enable concurrent browser tests with `async: true`: see [Ecto Sandbox](#ecto-sandbox)

7. (Optional) LLM usage rules for AI coding agents (via [usage_rules](https://hex.pm/packages/usage_rules))

    ```elixir
    # mix.exs
    def project do
      [
        ...
        usage_rules: usage_rules()
      ]
    end

    defp usage_rules do
      [
        # Option A: inline into a rules file
        file: "AGENTS.md", # or "CLAUDE.md"
        usage_rules: [~r/^phoenix/],
        # Option B: generate as skill (can be used instead of or in addition to file)
        skills: [
          location: ".agents/skills", # or ".claude/skills"
          deps: [:phoenix_test_playwright]
        ]
      ]
    end
    ```

    Then run `mix usage_rules.sync`.

> **Reference project**
>
> [github.com/ftes/phoenix_test_playwright_example](https://github.com/ftes/phoenix_test_playwright_example)
>
> The last commit adds a feature test for the `phx gen.auth` registration page
> and runs it in CI (Github Actions).


## Configuration

```elixir
# config/test.exs
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
```

See `PhoenixTest.Playwright.Config` for more details.

You can override some options in your test:

```elixir
defmodule DebuggingFeatureTest do
  use PhoenixTest.Playwright.Case,
    async: true,
    # Launch new browser for this test suite with custom options below
    browser_pool: false,
    # Show browser and pause 1 second between every interaction
    headless: false,
    slow_mo: :timer.seconds(1)
end
```


## Remote Playwright Server

Connect to a remote Playwright server via WebSocket instead of spawning a local
Node.js driver. Useful for Alpine Linux containers (glibc issues) or containerized CI.

```elixir
# mix.exs
{:websockex, "~> 0.4", only: :test}

# config/test.exs
config :phoenix_test, playwright: [ws_endpoint: "ws://localhost:3000", browser_pool: false]

# or, to enable via environment variable
config :phoenix_test, playwright: [ws_endpoint: System.get_env("PLAYWRIGHT_WS_ENDPOINT"), browser_pool: false]
```

```sh
# Start Playwright server
docker run -p 3000:3000 --rm --init -it --workdir /home/pwuser --user pwuser mcr.microsoft.com/playwright:v1.58.0-noble /bin/sh -c "npx -y playwright@1.58.0 run-server --port 3000 --host 0.0.0.0"
```

The browser type is automatically appended as a query parameter (e.g., `?browser=chromium`).


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

### Step annotations

Playwright traces support [grouping labelled test steps](https://playwright.dev/docs/api/class-tracing#tracing-group) and
assigning them source code locations. This makes it easier to see what a test
is doing and where. These groups are visible in the Playwright trace viewer.

```elixir
test "user registration", %{conn: conn} do
  conn
  |> visit(~p"/")
  |> step("Submit registration form", fn conn ->
    conn
    |> fill_in("Email", with: "user@example.com")
    |> fill_in("Password", with: "secret")
    |> click_button("Sign up")
  end)
  |> assert_has(".flash", text: "Welcome!")
end
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


## Logging in

For username/password login, just visit the login page and fill in the credentials:

```elixir
conn
|> visit(~p"/users/log_in")
|> fill_in("Email", with: "user@example.com")
|> fill_in("Password", with: "password123")
|> click_button("Sign in")
```

For magic link / passwordless login, see the [Emails](#emails) section below.


## Emails

If you want to verify the HTML of sent emails in your feature tests,
consider using `Plug.Swoosh.MailboxPreview`.
The iframe used to render the email HTML body makes this slightly tricky:

```elixir
|> visit(~p"/dev/mailbox")
|> click_link("Confirmation instructions")
|> within("iframe >> internal:control=enter-frame", fn conn ->
  conn
  |> click_link("Confirm account")
  |> click_button("Confirm my account")
  |> assert_has("#flash-info", text: "User confirmed")
end)
```


## Common problems

### Test failure in CI (timeout)

- Limit concurrency: `config :phoenix_test, playwright: [browser_pools: [[size: 1]]]` or `mix test --max-cases 1` for GitHub CI shared runners
- Increase timeout: `config :phoenix_test, playwright: [timeout: :timer.seconds(4)]`
- More compute power: e.g. `x64 8-core` [GitHub runner](https://docs.github.com/en/enterprise-cloud@latest/actions/using-github-hosted-runners/using-larger-runners/about-larger-runners#machine-sizes-for-larger-runners)

### LiveView not connected

```elixir
|> visit(~p"/")
|> assert_has("body .phx-connected")
# now continue, playwright has waited for LiveView to connect
```

### LiveComponent not connected

```html
<div id="my-component" data-connected={connected?(@socket)}>
```

```elixir
|> visit(~p"/")
|> assert_has("#my-component[data-connected]")
# now continue, playwright has waited for LiveComponent to connect
```

### Browser version mismatch

If you've installed a browser but can't run tests
(`Executable doesn't exist at .../ms-playwright/chromium_headless_shell-1208/`),
you probably used the wrong playwright JS version to install the browser.

Each playwright JS version pins a specific browser version.
Tests are run using `./assets/node_modules/playwright`
(see `assets_dir` in `PhoenixTest.Playwright.Config`).
Make sure to use that same playwright JS version to install the browser,
e.g. via `npx --prefix assets playwright install`.


## Ecto Sandbox

Make sure you have followed the advanced set up instructions for `Phoenix.Ecto.SQL.Sandbox`
- [with LiveViews](`Phoenix.Ecto.SQL.Sandbox#module-acceptance-tests-with-liveviews`)
- [with Channels](`Phoenix.Ecto.SQL.Sandbox#module-acceptance-tests-with-channels`)
- [with Ash authentication](https://hexdocs.pm/ash_authentication_phoenix/AshAuthentication.Phoenix.LiveSession.html#ash_authentication_live_session/3): use `on_mount_prepend`

`PhoenixTest.Playwright.Case` takes care of the rest. It starts the
sandbox under a separate process than your test and uses
`ExUnit.Callbacks.on_exit/1` to ensure the sandbox is shut down afterward. It
also sends a `User-Agent` header with the
`Phoenix.Ecto.SQL.Sandbox` metadata for your Ecto repos. This allows
the sandbox to be shared with the LiveView and other processes which need to
use the database inside the same transaction as the test. It also allows for
[concurrent browser tests](`e:phoenix_ecto:main#concurrent-browser-tests`).

```elixir
defmodule MyTest do
  use PhoenixTest.Playwright.Case, async: true
end
```

### Ownership errors with LiveViews

Unlike `Phoenix.LiveViewTest`, which controls the lifecycle of LiveView
processes being tested, Playwright tests may end while such processes are
still using the sandbox.

In that case, you may encounter ownership errors like:

```
** (DBConnection.OwnershipError) cannot find owner for ...
```

To prevent this, the `ecto_sandbox_stop_owner_delay` option allows you to delay the
sandbox owner's shutdown, giving LiveViews and other processes time to close
their database connections. The delay happens during
`ExUnit.Callbacks.on_exit/1`, which blocks the running of the next test, so
it affects test runtime as if it were a `Process.sleep/1` at the end of your
test.

So you probably want to use **as small a delay as you can**, and only for the
tests that need it, using `@tag` (or `@describetag` or `@moduletag`) like:

```elixir
@tag ecto_sandbox_stop_owner_delay: 100 # 100ms
test "does something" do
  # ...
end
```

If you want to set a global default, you can:

```elixir
# config/test.exs
config :phoenix_test, playwright: [
  ecto_sandbox_stop_owner_delay: 50  # 50ms
]
```


## Missing Playwright features

This library adds functions beyond the standard PhoenixTest API (e.g. `screenshot/3`, `evaluate/2`, `click_link/4`),
but it does not wrap the entire Playwright API.

You can add any missing functionality yourself using `unwrap/2` with
[PlaywrightEx](https://hexdocs.pm/playwright_ex) modules (`Frame`, `Selector`, `Page`, `BrowserContext`),
and the [Playwright source](https://github.com/microsoft/playwright/blob/main/packages/playwright-core/src/client/frame.ts).

If you think others might benefit, please [open a PR](https://github.com/ftes/phoenix_test_playwright/pulls).

Here is some inspiration:

```elixir
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
```


## Contributing

To run the tests locally, you'll need to:

1. Check out the repo
2. Run `mix setup`. This will take care of setting up your dependencies, installing the JavaScript dependencies (including Playwright), and compiling the assets.
3. Run `mix test` or, for a more thorough check that matches what we test in CI, run `mix check`
4. Run `mix test.websocket` to run all tests against a 'remote' playwright server via websocket. Docker needs to be installed. A container is started via `testcontainers`.

### Conventions

- **Follows PhoenixTest API.** Only add new public functions when strictly necessary for browser-specific interaction (e.g., screenshots, JS evaluation).
- **Do not edit upstream tests.** Files under `test/phoenix_test/upstream/` are mirrored from [phoenix_test](https://github.com/germsvel/phoenix_test) and must not be modified. Playwright-specific tests go in `test/phoenix_test/playwright_test.exs` or other files outside `upstream/`.

### Playwright internals

Playwright's implementation is split between a **client** (Node.js API) and a **server** (browser protocol layer). The [Playwright docs](https://playwright.dev/docs/intro) describe the public API but don't reflect this split. When reading Playwright source code, it can help to look at the TypeScript sources directly: [client](https://github.com/microsoft/playwright/tree/main/packages/playwright-core/src/client) and [server](https://github.com/microsoft/playwright/tree/main/packages/playwright-core/src/server) (locally under `priv/static/assets/node_modules/playwright-core/lib/`).
