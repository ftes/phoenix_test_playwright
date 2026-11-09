# PhoenixTest.Playwright

Playwright driver for [PhoenixTest](https://hexdocs.pm/phoenix_test). Run feature tests in a real browser using the standard PhoenixTest API.

Use this when you need to test JavaScript behavior, browser-specific quirks, or anything requiring a real browser.

## Key principles

- Prefer the standard PhoenixTest API (`visit`, `click_link`, `click_button`, `fill_in`, `assert_has`, etc.)
- Only use Playwright-specific functions when the standard API doesn't cover your use case
- The `conn` in tests is NOT a `Plug.Conn` — it's a Playwright session. We use the name `conn` so tests can easily switch between PhoenixTest drivers.

## Setup

This assumes [PhoenixTest](https://hexdocs.pm/phoenix_test) and [PhoenixTest.Playwright](https://hexdocs.pm/phoenix_test_playwright/readme.md#getting-started) have been set up (dependencies, config, Ecto sandbox, `test_helper.exs`).

## Test example

```elixir
defmodule MyApp.Features.SomeTest do
  # Ecto sandbox is managed automatically — do not set it up manually
  use PhoenixTest.Playwright.Case, async: true
  use MyAppWeb, :verified_routes

  test "example", %{conn: conn} do
    conn
    |> visit(~p"/")
    |> click_link("Sign in")
    |> fill_in("Email", with: "user@example.com")
    |> click_button("Submit")
    |> assert_has(".success", text: "Welcome")
  end
end
```

## Beyond the standard PhoenixTest API

This library adds browser-specific functions (e.g. `screenshot/3`, `evaluate/2`, `type/4`, `press/4`, `drag/3`). See the [docs](https://hexdocs.pm/phoenix_test_playwright/PhoenixTest.Playwright.md) for the full list.

For anything the library doesn't cover, use `unwrap/2` to access `PlaywrightEx` modules (`Page`, `Locator`, `Frame`, `BrowserContext`) directly, or `evaluate/2` for simple JavaScript (see [Missing Playwright features](https://hexdocs.pm/phoenix_test_playwright/readme.md#missing-playwright-features)):

```elixir
# Listen to page-level events (e.g. console messages)
conn
|> unwrap(fn %{page: page} -> PlaywrightEx.Page.on(page, :console, &IO.inspect/1) end)
```

When calling `PlaywrightEx` directly, follow its [usage rules](deps/playwright_ex/usage-rules.md).

## Debugging

- `@tag trace: :open` — record and open interactive trace viewer
- `@tag screenshot: true` — auto-capture screenshot on failure
- `open_browser/1` — open current page in system browser

## Logging in

Visit the login form and fill it in with the standard PhoenixTest API, or use `add_session_cookie/3` to skip it. See [Logging in](https://hexdocs.pm/phoenix_test_playwright/readme.md#logging-in).

For magic link / passwordless login, see the [Emails section](https://hexdocs.pm/phoenix_test_playwright/readme.md#emails) in the docs.

## Common problems

### LiveView not connected
`visit/2` can return before LiveView has connected, and an action taken before that is lost. Wait for the connection first:
```elixir
|> visit(~p"/")
|> assert_has("body .phx-connected")
# now continue, Playwright has waited for LiveView to connect
```
For LiveComponents, add `data-connected={connected?(@socket)}` and assert on that attribute instead.

[Fluffy](https://hex.pm/packages/fluffy) waits for every LiveView to connect after each navigation in the browser, including one triggered by a click or form submit.

### Test failures, browser version mismatch, Ecto ownership errors
See [Common problems](https://hexdocs.pm/phoenix_test_playwright/readme.md#common-problems) and [Ownership errors](https://hexdocs.pm/phoenix_test_playwright/readme.md#ownership-errors-with-liveviews).

## Fetching documentation

This library runs in the test environment, so docs are not available via Tidewave or similar dev tools. Fetch and cache the hexdocs yourself:
- https://hexdocs.pm/phoenix_test_playwright/readme.md
- https://hexdocs.pm/phoenix_test_playwright/PhoenixTest.Playwright.md
- https://hexdocs.pm/phoenix_test_playwright/PhoenixTest.Playwright.Case.md
- https://hexdocs.pm/phoenix_test_playwright/PhoenixTest.Playwright.Config.md
