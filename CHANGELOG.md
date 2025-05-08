# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased
### Added
- Dialog handling
  - Config option `accept_dialogs` (default: `true`)
  - `PhoenixTest.Playwright.with_dialog/3` for conditional handling

## [0.6.3] 2025-05-05
### Added
- Add locale to avoid console warnings. Commit [becf5e6] @peaceful-james

### Fixed
- Trigger `phx-change` event for input with `phx-debounce="blur"`. Commit [72edd9]

## [0.6.2] 2025-04-24
### Changed
- `Frame.evaluate/3`: Don't transform map keys in return value. Example: `js {camelCase: {a: 1}} -> ex %{"camelCase": %{"a": 1}}`. Previously attempted to underscore and atom-ize keys, which led to issue [#24](https://github.com/ftes/phoenix_test_playwright/pull/24). Commit [5ff530]

## [0.6.1] 2025-04-02
### Added
- Support relevant `phoenix_test 0.6` features
  - ✅ Deprecate `select` with `:from` in favor of `:option` (handled by `PhoenixTest`)
  - ✅ Allow nesting of `within/3`
  - ✅ Allow calling `visit/2` sequentially (was already supported)
  - ❌ Raise error when visiting a defined route: In a feature test, we assert on the rendered page, not the status code.

## [0.6.0] 2025-03-18
### Added
- Add and remove cookies: `add_cookies/2`, `add_session_cookie/3`, `clear_cookies/{1,2}` @peaceful-james
- Add option `browser_launch_timeout` for more fine-grained control (is typically a lot slower than other actions) @s3cur3

## [0.5.0] 2025-02-14
### Added
- Docs: Document and validate global and per-test configuration
- Docs: Document non-standard driver functions (`click/4`, `click_button/4` etc.). Also, exclude standard driver functions from docs.
- Config: Override config via `Case` opts, e.g. `use PhoenixTest.Playwright.Case, headless: false`
- Keyboard simulation: `type/{3,4}` and `press/{3,4}`

### Changed
- Renamed: `PheonixTest.Case` to `PhoenixTest.Playwright.Case`
  ```diff
     defmodule MyTest do
  -    use PhoenixTest.Case, async: true
  +    use PhoenixTest.Playwright.Case, async: true
  -    @moduletag :playwright
  ```

## [0.4.0] 2025-02-03
### Added
- Screenshots: `screenshot/{2,3}` function and `screenshot: true` config for auto-capture @s3cur3

### Changed
- Config: flattened list (remove nested `browser` config), override via top-level ExUnit `@tag ...`s (remove nested `@tag playwright: [...]`)
  ```diff
     # config/test.exs
     config :phoenix_test,
       playwright: [
  -      browser: [browser: :chromium, headless: false, slow_mo: 0]
  +      browser: :chromium,
  +      headless: false,
  +      slow_mo: 0
  ```

## [0.3.0] 2025-01-26
### Changed
- Auto-convert case of playwright messages keys (snake_case to camelCase)

## [0.2.1] 2025-01-17
### Added
- Add more config options (browser, JS console) @s3cur3

### Changed
- Improve error messages @s3cur3
- Improve setup and docs for contributors @s3cur3

## [0.2.0] 2025-01-09
### Added
- support `phoenix_test@0.5`, `elixir@1.18`, `phoenix_live_view@1.0`

## [0.1.5] 2024-12-15
### Added
- `@tag trace: :open` to auto open recorded Playwright trace in viewer

[5ff530]: https://github.com/ftes/phoenix_test_playwright/commit/5ff530
[becf5e]: https://github.com/ftes/phoenix_test_playwright/commit/becf5e
[72edd9]: https://github.com/ftes/phoenix_test_playwright/commit/72edd9
