[![Hex.pm Version](https://img.shields.io/hexpm/v/phoenix_test_playwright)](https://hex.pm/packages/phoenix_test_playwright)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/phoenix_test_playwright/)
[![License](https://img.shields.io/hexpm/l/phoenix_test_playwright.svg)](https://github.com/ftes/phoenix_test_playwright/blob/main/LICENSE.md)
[![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/ftes/phoenix_test_playwright/elixir.yml)](https://github.com/ftes/phoenix_test_playwright/actions)

# PhoenixTestPlaywright

Execute [PhoenixTest](https://hexdocs.pm/phoenix_test) cases in an actual browser via [Playwright](https://playwright.dev/).
Locator matching follows Playwright's browser-oriented semantics; see [Locator semantics](#locator-semantics).

```elixir
defmodule Features.RegisterTest do
  use PhoenixTest.Playwright.Case,
    async: true,                         # async with Ecto sandbox
    parameterize: [                      # run in multiple browsers in parallel
      %{browser: :chromium},
      %{browser: :firefox}
    ]

  @tag trace: :on                        # record a trace into test-results/
  test "register", %{conn: conn} do
    conn
    |> visit("/")
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
    {:phoenix_test_playwright, "~> 0.20.0-rc.0", only: :test, runtime: false}
    ```

2. Install the Playwright driver and browser (no Node.js or npm needed, see [Playwright driver](#playwright-driver))

    ```sh
    MIX_ENV=test mix playwright_ex.install -- chromium --with-deps
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
    Application.put_env(:phoenix_test, :base_url, YourAppWeb.Endpoint.url())
    ```

    Browsers come from `PlaywrightEx.Test.BrowserPool`: launched on first use, and stopped
    after the suite.

5. Use in test

    ```elixir
    defmodule MyTest do
      use PhoenixTest.Playwright.Case
      use YourAppWeb, :verified_routes # for `~p`

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
        usage_rules: [~r/^phoenix/, :playwright_ex],
        # Option B: generate as skill (can be used instead of or in addition to file)
        skills: [
          location: ".agents/skills", # or ".claude/skills"
          deps: [:phoenix_test_playwright, :playwright_ex]
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

## Ecto Sandbox

Make sure you have followed the advanced set up instructions for `Phoenix.Ecto.SQL.Sandbox`
- [with LiveViews](https://hexdocs.pm/phoenix_ecto/Phoenix.Ecto.SQL.Sandbox.html#module-acceptance-tests-with-liveviews)
- [with Channels](https://hexdocs.pm/phoenix_ecto/Phoenix.Ecto.SQL.Sandbox.html#module-acceptance-tests-with-channels)
- [with Ash authentication](https://hexdocs.pm/ash_authentication_phoenix/AshAuthentication.Phoenix.LiveSession.html#ash_authentication_live_session/3): use `on_mount_prepend`

`PhoenixTest.Playwright.Case` takes care of the rest. It starts the
sandbox under a separate process than your test and uses
`ExUnit.Callbacks.on_exit/1` to ensure the sandbox is shut down afterward. It
also sends a `User-Agent` header with the
`Phoenix.Ecto.SQL.Sandbox` metadata for your Ecto repos. This allows
the sandbox to be shared with the LiveView and other processes which need to
use the database inside the same transaction as the test. It also allows for
[concurrent browser tests](https://hexdocs.pm/phoenix_ecto/main.html#concurrent-browser-tests).

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


## Locator semantics

PhoenixTestPlaywright uses Playwright's native label and role locators. This
keeps browser tests aligned with Playwright's auto-waiting, strictness, and
accessible-name behavior, but it intentionally differs from PhoenixTest's HTML
parser in a few edge cases:

- `click_link/2` and `click_button/2` match the computed accessible name. An
  `aria-labelledby` or `aria-label` therefore overrides visible text, and a
  substring may match ARIA names that PhoenixTest's HTML driver would ignore
  after finding a visible-text match.
- Form actions and `assert_has(label: ...)` use Playwright's label locator. If
  a control has both an HTML `<label>` and an ARIA name, use the ARIA name.
  Label assertions default to substring matching and honor `exact: true` for a
  complete-label match.
- Playwright's label locator matches each `aria-labelledby` reference
  separately; it does not match one string spanning multiple referenced
  elements. Prefer one referenced element containing the complete label, or
  use `aria-label`.

These differences only matter when an element has competing names or an
`aria-labelledby` value referencing multiple elements. Ordinary HTML labels,
`aria-label`, and single-reference `aria-labelledby` locators work across
links, buttons, form actions, and assertions.

Playwright's native option selection matches option labels exactly. Therefore,
`select(..., exact_option: false)` is not supported; use the option's complete
label with the default `exact_option: true` behavior.


## Configuration

```elixir
# config/test.exs
config :phoenix_test,
  otp_app: :your_app,
  playwright: [js_logger: nil]

# Browsers, context options, traces, screenshots, videos and snapshot paths, see PlaywrightEx.Test
config :playwright_ex, :test,
  browser_name: :chromium,
  launch_options: [timeout: 10_000],
  context_options: [locale: "de-DE"],
  action_timeout: 2_000,
  trace: :retain_on_failure

# Assertion timeout, 5 seconds by default
config :playwright_ex, :expect, timeout: 2_000
```

See `PhoenixTest.Playwright.Config` for more details, including timeout semantics.

Each test module gets a browser of its own from `PlaywrightEx.Test.BrowserPool`, as a Playwright Test
worker does: at most `config :playwright_ex, :test, workers: ...` at once (half the schedulers by default),
reused warm by the next module. Each test gets a fresh browser context.

You can override some options per test module, merged over `config :playwright_ex, :test`:

```elixir
defmodule DebuggingFeatureTest do
  use PhoenixTest.Playwright.Case,
    async: true,
    # Show browser and pause 1 second between every interaction
    browser_launch_opts: [headless: false, slow_mo: :timer.seconds(1)]
end
```

And browser context options per test: `@tag browser_context_opts: [locale: "fr-FR"]`.


## Playwright driver

PlaywrightEx pins the Playwright version and downloads its driver (Node.js and `playwright-core`)
to `PLAYWRIGHT_EX_CACHE_DIR` (default: `playwright_ex` in the user cache directory) on first use.
Browsers go to `PLAYWRIGHT_BROWSERS_PATH` (default: `ms-playwright` in the user cache directory).

To bring your own, set one of these environment variables:
- `PLAYWRIGHT_EX_EXECUTABLE`: a `playwright` CLI, e.g. `assets/node_modules/.bin/playwright`. Its version must match `PlaywrightEx.Driver.version/0`.
- `PLAYWRIGHT_NODEJS_PATH`: a Node.js binary to run the pinned driver with, e.g. on Alpine Linux.

Cache both directories in CI. Keep the install step on a cache hit, as `--with-deps` installs system packages.

```yaml
# .github/workflows/elixir.yml
- uses: actions/cache@v4
  with:
    path: |
      ~/.cache/playwright_ex
      ~/.cache/ms-playwright
    key: playwright-${{ runner.os }}-${{ hashFiles('mix.lock') }}
- run: mix playwright_ex.install -- chromium --with-deps
  env:
    MIX_ENV: test
```


## Remote Playwright Server

Run browsers on a remote Playwright server instead of launching them locally.
Useful for containerized CI.

`PlaywrightEx.Test.BrowserPool` connects instead of launching when `connect_options` are configured
(Playwright Test's `connectOptions`). Traces, screenshots and videos are recorded as for local browsers.

The connection goes through a local Playwright driver, which PlaywrightEx downloads on
first use. Its Node.js binary needs glibc: on Alpine Linux, install `nodejs` and set
`PLAYWRIGHT_NODEJS_PATH` to it. The server must run the same Playwright version.

```elixir
# config/test.exs
config :playwright_ex, :test, connect_options: [ws_endpoint: "ws://localhost:3000"]

# or, to enable via environment variable
config :playwright_ex, :test,
  connect_options: if(url = System.get_env("PLAYWRIGHT_WS_ENDPOINT"), do: [ws_endpoint: url])
```

```sh
# Start Playwright server
docker run -p 3000:3000 --rm --init -it --workdir /home/pwuser --user pwuser mcr.microsoft.com/playwright:v1.65.0-noble /bin/sh -c "npx --yes playwright@1.65.0 run-server --port 3000 --host 0.0.0.0"
```

The browser type is sent in the `x-playwright-browser` header when connecting.


## Traces

Playwright traces record a full browser history, including 'user' interaction, browser console, network transfers etc.
Traces can be explored in an interactive viewer for debugging purposes.

Traces are recorded by `PlaywrightEx.Test`, as configured by `config :playwright_ex, :test, trace: ...`
(`:off` by default, `:on`, `:retain_on_failure`) and the `trace` tag:

```elixir
@tag trace: :on
test "record a trace into test-results/<test>/trace.zip" do
```

Open it in the viewer with `mix playwright_ex.cli show-trace test-results/<test>/trace.zip`
(a failed test that keeps a trace prints this command).

### Step annotations

Use `PhoenixTest.Playwright.step/3` to label test steps (`PlaywrightEx.Test.step`, Playwright Test's `test.step`)
with their source code locations. Steps nest, and are visible in the Playwright trace viewer.

## Screenshots

### Manually

```elixir
|> visit(~p"/")
|> screenshot("home.png")    # captures entire page by default, into test-results/<test>/home.png
```

### Visual regression

```elixir
|> assert_screenshot("home.png")  # test/<test file>-snapshots/home-<platform>.png
```

Baselines are resolved as in Playwright Test (`snapshot_dir`, `snapshot_path_template` in
`config :playwright_ex, :test`), and comparison output goes to `test-results/<test>/`.


## Traces and screenshots for failed tests in CI

```elixir
# config/test.exs
config :playwright_ex, :test,
  trace: :retain_on_failure,
  screenshot: :only_on_failure
```

Failed tests keep their files in `test-results/<test>/`, including an `error-context.md`.
Add `test-results/` to `.gitignore` and upload it as a CI artifact on failure.
Tracing slows every test, so you may prefer to trace only when re-running failures:

```elixir
# config/test.exs
config :playwright_ex, :test, trace: if(System.get_env("PW_TRACE"), do: :on, else: :off)
```

```yaml
# .github/workflows/elixir.yml
run: "mix test || if [[ $? = 2 ]]; then PW_TRACE=true mix test --failed; else false; fi"
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

To skip the login form, for example in tests that aren't about logging in, add a session cookie with `PhoenixTest.Playwright.add_session_cookie/3`:

```elixir
conn
|> add_session_cookie(
  [value: %{user_token: Accounts.generate_user_session_token(user)}],
  MyAppWeb.Endpoint.session_options()
)
|> visit(~p"/")
```

A generated Phoenix endpoint only has a `@session_options` attribute, so expose it with `def session_options, do: @session_options`.

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

- Tune concurrency: `config :playwright_ex, :test, workers: ...` (browsers, half the cores by default) and `mix test --max-cases ...`.
  For suites that wait on the app, `workers` near the core count with `--max-cases` about the core count tends to be fastest;
  more starves the app and causes timeouts. On small GitHub CI shared runners, try `workers: 1`.
- Run one browser per `mix test` (e.g. `--only` a tag, or CI partitions): switching browser or launch options restarts a worker.
- Increase timeouts: `config :playwright_ex, :expect, timeout: 10_000` for assertions, `config :playwright_ex, :test, action_timeout: ...` for actions
- More compute power: e.g. `x64 8-core` [GitHub runner](https://docs.github.com/en/enterprise-cloud@latest/actions/using-github-hosted-runners/using-larger-runners/about-larger-runners#machine-sizes-for-larger-runners)

### LiveView not connected

`visit/2` returns at the page's `load` event, which can be before LiveView has connected. An action taken before that is lost, so a longer timeout doesn't help. Wait for the connection first:

```elixir
|> visit(~p"/")
|> assert_has("body .phx-connected")
# now continue, playwright has waited for LiveView to connect
```

Or use [Fluffy](https://hex.pm/packages/fluffy), which waits for every LiveView to connect after each navigation in the browser, including one triggered by a click or form submit. See its [migration guide](https://hexdocs.pm/fluffy/migration-from-phoenix-test.html).

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
Tests are run using the driver pinned by PlaywrightEx (see `PlaywrightEx.Driver.version/0`).
Make sure to use that same driver to install the browser,
e.g. via `MIX_ENV=test mix playwright_ex.install -- chromium`.


## Missing Playwright features

This library adds functions beyond the standard PhoenixTest API (e.g. `screenshot/3`, `evaluate/2`, `click_link/4`),
but it does not wrap the entire Playwright API.

You can add any missing functionality yourself using `unwrap/2` with
[PlaywrightEx](https://hexdocs.pm/playwright_ex) modules (`Page`, `Locator`, `Frame`, `BrowserContext`),
which follow the [Playwright docs](https://playwright.dev/docs/api/class-playwright).

If you think others might benefit, please [open a PR](https://github.com/ftes/phoenix_test_playwright/pulls).

Here is some inspiration:

```elixir
def choose_styled_radio_with_hidden_input_button(conn, label, opts \\ []) do
  opts = Keyword.validate!(opts, exact: true)
  PhoenixTest.Playwright.click(conn, PhoenixTest.Playwright.Selector.text(label, opts))
end

def assert_a11y(conn) do
  conn
  |> evaluate(A11yAudit.JS.axe_core())
  |> evaluate("axe.run()", fn json ->
    results = A11yAudit.Results.from_json(json)
    A11yAudit.Assertions.assert_no_violations(results)
  end)
end

def within_iframe(conn, selector \\ "iframe", fun) when is_function(fun, 1) do
  within(conn, "#{selector} >> internal:control=enter-frame", fun)
end
```


## Contributing

See [CONTRIBUTING.md](https://github.com/ftes/phoenix_test_playwright/blob/main/CONTRIBUTING.md).
