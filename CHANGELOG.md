# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
<!-- and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). -->


## [0.10.0-rc.1]

### Fixed
- Correctly handle custom options via `browser_context_opts` and `browser_page_opts`. Commit [6182699]

## [0.10.0-rc.0] 2025-11-19
### Breaking changes
- Use browser pool by default, instead of starting new browser per test suite. Commit [095e216]
  ```diff
    # test_helper.exs
  + {:ok, _} = PhoenixTest.Playwright.Supervisor.start_link()
    Application.put_env(:phoenix_test, :base_url, MyAppWeb.Endpoint.url())
  ```
- Changes required if internals (beyond `PhoenixTest` and `PhoenixTest.Playwright` modules) were used. Phoenix-agnostic modules moved to `PlaywrightEx`, with slight API changes. Example:
  ```diff
  - |> unwrap(& {:ok, _} = PhoenixTest.Playwright.Frame.click(&1.frame_id, selector))
  + |> unwrap(& {:ok, _} = PlaywrightEx.Frame.click(&1.frame_id, selector: selector, timeout: timeout())
  ```
### Changed
- Ecto sandbox ownership: Use a separate sandbox owner process instead of the test process. This reduces ownership errors when LiveViews continue to use database connections after the test terminates. Commit [3b54699]
### Added
- Config option `ecto_sandbox_stop_owner_delay`: Delay in milliseconds before shutting down the Ecto sandbox owner. Use when LiveViews or other processes need time to stop using the connections. Commit [2f4a8cf]

## [0.9.1] 2025-10-29
### Added
- Browser pooling (opt-in): Reduced memory, higher speed.. Commit [00e75c6]

## [0.9.0] 2025-10-26
### Fixed
- `assert_has/refute_has`: don't raise if multiple nodes found when using `value` option (playwright strict mode). Commit [73ebf10]
### Changed
- Return result tuples from all playwright channel functions for consistency and to surface errors early. Commit [ae63989]
  - Most notably may affect callers of `Frame.evaluate/3`
### Added
- Register custom selector engines via new config option `selector_engines`. Commit [73ebf10]
- Import click/2 in Playwright.Case. Commit [968d5cd]
- Add drag and drop: `drag(source, to: target)`. Commit [f4161bd]

## [0.8.0] 2025-09-17
### Removed
- Config option `cli`. Use `assets_dir` instead. Commit [9e95e54]

### Added
- Support `bunx` JS runner. Added config options `runner` and `assets_dir`. Commit [9e95e54]
- Support missing `assert_has/refute_has` options: `label` and `value`. Commit [2e92cbe]
- Support `phoenix_test` `0.8` (lazy_html). Commit [1074cde]

### Changed
- Include source location when logging javascript errors and browser console logs. Commit [6b148f]
- Only consider visible inputs for fill_in etc. Commit [86c2e3d]
- Speed up `refute_has`: Use playwright browser internal retry. Commit [aac0497]

## [0.7.1] 2025-07-01
### Added
- Config option `executable_path`: allow using existing browser executable instead of bundled browser (e.g. on NixOS). Commit [15df46]
### Fixed
- `refute_has/3` add retry, don't fail if element initially found. Commit [7bd49b]

## [0.7.0] 2025-06-16
### Added
- Dialog handling. Commit [4eadea]
  - Config option `accept_dialogs` (default: `true`)
  - `PhoenixTest.Playwright.with_dialog/3` for conditional handling

### Removed
- `Connection.received/1`. Commit [4eadea]
  - Use `EventRecorder` instead

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

[3b54699]: https://github.com/ftes/phoenix_test_playwright/commit/3b54699
[5ff530]: https://github.com/ftes/phoenix_test_playwright/commit/5ff530
[becf5e]: https://github.com/ftes/phoenix_test_playwright/commit/becf5e
[72edd9]: https://github.com/ftes/phoenix_test_playwright/commit/72edd9
[15df46]: https://github.com/ftes/phoenix_test_playwright/commit/15df46
[7bd49b]: https://github.com/ftes/phoenix_test_playwright/commit/7bd49b
[4eadea]: https://github.com/ftes/phoenix_test_playwright/commit/4eadea
[6b148f]: https://github.com/ftes/phoenix_test_playwright/commit/6b148f
[9e95e54]: https://github.com/ftes/phoenix_test_playwright/commit/9e95e54
[2e92cbe]: https://github.com/ftes/phoenix_test_playwright/commit/2e92cbe
[6b148f]: https://github.com/ftes/phoenix_test_playwright/commit/6b148f
[1074cde]: https://github.com/ftes/phoenix_test_playwright/commit/1074cde
[86c2e3d]: https://github.com/ftes/phoenix_test_playwright/commit/86c2e3d
[aac0497]: https://github.com/ftes/phoenix_test_playwright/commit/aac0497
[73ebf10]: https://github.com/ftes/phoenix_test_playwright/commit/73ebf10
[ae63989]: https://github.com/ftes/phoenix_test_playwright/commit/ae63989
[968d5cd]: https://github.com/ftes/phoenix_test_playwright/commit/968d5cd
[f4161bd]: https://github.com/ftes/phoenix_test_playwright/commit/f4161bd
[00e75c6]: https://github.com/ftes/phoenix_test_playwright/commit/00e75c6
[2f4a8cf]: https://github.com/ftes/phoenix_test_playwright/commit/2f4a8cf
[095e216]: https://github.com/ftes/phoenix_test_playwright/commit/095e216
[6182699]: https://github.com/ftes/phoenix_test_playwright/commit/6182699
