# PhoenixTest.Playwright

Playwright driver for [PhoenixTest](https://hexdocs.pm/phoenix_test). Run feature tests in a real browser using the standard PhoenixTest API.

Use this when you need to test JavaScript behavior, browser-specific quirks, or anything requiring a real browser.

## Key principles

- Prefer the standard PhoenixTest API (`visit`, `click_link`, `click_button`, `fill_in`, `assert_has`, etc.)
- Only use Playwright-specific functions when the standard API doesn't cover your use case
- The `conn` in tests is NOT a `Plug.Conn` — it's a Playwright session. We use the name `conn` so tests can easily switch between PhoenixTest drivers.

## Setup

This assumes [PhoenixTest](https://hexdocs.pm/phoenix_test) and [PhoenixTest.Playwright](https://hexdocs.pm/phoenix_test_playwright/PhoenixTest.Playwright.md#module-getting-started) have been set up (dependencies, config, Ecto sandbox, `test_helper.exs`).

## Test example

```elixir
defmodule MyApp.Features.SomeTest do
  # Ecto sandbox is managed automatically — do not set it up manually
  use PhoenixTest.Playwright.Case, async: true

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

This library adds browser-specific functions (e.g. `screenshot/2`, `evaluate/2`, `type/3`, `press/3`, `drag/3`). See the [docs](https://hexdocs.pm/phoenix_test_playwright/PhoenixTest.Playwright.md) for the full list.

For anything the library doesn't cover, use `unwrap/2` to access `PlaywrightEx` modules (`Frame`, `Selector`, `Page`, `BrowserContext`) directly, or `evaluate/2` for simple JavaScript (see [Missing Playwright features](https://hexdocs.pm/phoenix_test_playwright/readme.md#missing-playwright-features)):

```elixir
# Subscribe to page-level events (e.g. downloads)
conn
|> unwrap(fn %{page_id: page_id} -> PlaywrightEx.subscribe(page_id) end)
```

## Debugging

- `@tag trace: :open` — record and open interactive trace viewer
- `@tag screenshot: true` — auto-capture screenshot on failure
- `open_browser/1` — open current page in system browser

## Logging in

For username/password login, just visit the login page and fill in the credentials:
```elixir
conn
|> visit(~p"/users/log_in")
|> fill_in("Email", with: "user@example.com")
|> fill_in("Password", with: "password123")
|> click_button("Sign in")
```

For magic link / passwordless login, see the [Emails section](https://hexdocs.pm/phoenix_test_playwright/readme.md#emails) in the docs.

## Common problems

### LiveView not connected
```elixir
|> visit(~p"/")
|> assert_has("body .phx-connected")
# now continue, Playwright has waited for LiveView to connect
```
For LiveComponents, add `data-connected={connected?(@socket)}` and assert on that attribute instead.

### Test failures, browser version mismatch, Ecto ownership errors
See the [docs](https://hexdocs.pm/phoenix_test_playwright/PhoenixTest.Playwright.md#module-common-problems).

## Fetching documentation

This library runs in the test environment, so docs are not available via Tidewave or similar dev tools. Fetch and cache the hexdocs yourself:
- https://hexdocs.pm/phoenix_test_playwright/PhoenixTest.Playwright.md
- https://hexdocs.pm/phoenix_test_playwright/PhoenixTest.Playwright.Case.md
- https://hexdocs.pm/phoenix_test_playwright/PhoenixTest.Playwright.Config.md
