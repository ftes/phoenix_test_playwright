# Upgrading to 0.20

phoenix_test_playwright 0.20 runs on Playwright (Hex package `playwright_ex`), a port of the official
Playwright client with a pinned Playwright 1.65 driver, and on its test runner, `Playwright.Test`.
Browsers, timeouts, traces, screenshots and snapshot paths are now configured as in Playwright Test,
in `config :playwright, :test`. This guide lists what a 0.19 suite must change, as one step from
0.19 (not release candidate to release candidate); the [changelog](../CHANGELOG.md) has the details.

## Setup

- Require Elixir 1.18 or newer.
- Name the release candidate in your requirement: `~> 0.14`, as the 0.19 README suggested, never
  selects one.

  ```diff
  # mix.exs
  - {:phoenix_test_playwright, "~> 0.14", only: :test, runtime: false}
  + {:phoenix_test_playwright, "~> 0.20.0-rc.0", only: :test, runtime: false}
  ```
- Playwright downloads its own driver, so Node.js and the npm `playwright` package are no longer
  needed: remove it from `assets/package.json`, drop the `assets_dir` option, and install the
  browser with Playwright's Mix task, in CI too
  ([Playwright driver](../README.md#playwright-driver) shows how to cache it):

  ```diff
  - pnpm --dir assets add --save-dev playwright
  - pnpm --dir assets exec playwright install chromium --with-deps
  + MIX_ENV=test mix playwright.install chromium --with-deps
  ```

  To keep your own CLI, set `config :playwright, :driver, executable: "assets/node_modules/.bin/playwright"`
  in `config/config.exs`; its version must match `Playwright.Driver.version/0`.
- Remove the supervisor from `test/test_helper.exs`: the module is gone, and browsers come from
  `Playwright.Test.BrowserPool`, launched on first use.

  ```diff
  # test/test_helper.exs
  - {:ok, _} = PhoenixTest.Playwright.Supervisor.start_link()
    Application.put_env(:phoenix_test, :base_url, YourAppWeb.Endpoint.url())
  ```
- `PlaywrightEx` is renamed `Playwright` (app `:playwright`, modules `Playwright.*`; the Hex package
  stays `playwright_ex`). If you list it yourself, replace `{:playwright_ex, ...}` with
  `{:playwright, "~> 1.65.0-rc.4", hex: :playwright_ex}`, rename `config :playwright_ex` to
  `config :playwright`, then run `mix deps.clean --unused --unlock`.
- For usage rules, add `:playwright` next to `~r/^phoenix/` (and to `skills: [deps: ...]`), see
  [Getting started](../README.md#getting-started).

## Configuration

`config :phoenix_test, :playwright` keeps `accept_dialogs`, `ecto_sandbox_stop_owner_delay`,
`js_logger` and `selector_engines`; any other key fails each browser test's setup. Move the rest to
Playwright:

```diff
# config/test.exs
-config :phoenix_test, :playwright,
-  browser: :chromium,
-  headless: false,
-  slow_mo: 500,
-  browser_launch_opts: [args: ["--use-fake-ui-for-media-stream"]],
-  browser_context_opts: [locale: "de"],
-  timeout: 2_000,
-  trace: true,
-  screenshot: true,
-  ws_endpoint: "ws://localhost:3000",
-  browser_pool: false
+config :playwright, :test,
+  browser_name: :chromium,
+  launch_options: [headless: false, slow_mo: 500, args: ["--use-fake-ui-for-media-stream"]],
+  context_options: [locale: "de"],
+  action_timeout: 2_000,
+  navigation_timeout: 2_000,
+  expect: [timeout: 2_000],
+  trace: :on,
+  screenshot: [mode: :on, full_page: true],
+  connect_options: [ws_endpoint: "ws://localhost:3000"]
```

- **Browser:** `browser` is `browser_name`. `headless`, `slow_mo` and `executable_path` go into
  `launch_options`. Drop `browser_launch_timeout`: launches get Playwright's default (3 minutes).
- **Pools:** drop `browser_pools`, `browser_pool`, `browser_pool_checkout_timeout`. Each test module
  holds a browser of its own, as a Playwright Test worker, and `workers` (half the schedulers by
  default) caps them.
- **Remote server:** `ws_endpoint` is `connect_options: [ws_endpoint: url]`. The connection goes
  through a local driver, so the test machine downloads it, and the server must run Playwright 1.65.
  Remove the `websockex` dependency, which is no longer needed. The driver's Node.js needs glibc:
  on Alpine Linux, install `nodejs` and set `config :playwright, :driver, node: ...` to it
  ([Remote Playwright Server](../README.md#remote-playwright-server)).
- **Timeouts:** `timeout` is gone. Actions and navigations have no timeout by default (the
  ExUnit test timeout bounds them), and assertions wait 5 seconds. To keep 0.19's 2 seconds for
  everything, set all three as above. An operation's `timeout:` still overrides them;
  `:infinity` is no limit. An assertion's `timeout: 0` checks once, but actions and
  `assert_screenshot/3` reject `0`.
- **Recording:** `trace` and `screenshot` take Playwright's values (`:on`, `:retain_on_failure`,
  `:on_first_retry`; `:on`, `:only_on_failure`), and `video` is new. 0.19's `true` recorded
  every test, so it is `:on`, as above; `:retain_on_failure` and `:only_on_failure` keep only
  failures' files. 0.19's screenshots were full page, while Playwright's capture the viewport unless
  `full_page: true`: the keyword form `screenshot: [full_page: ..., omit_background: ...]` is
  `screenshot: [mode: :on, full_page: ..., omit_background: ...]`. Files go to
  `test-results/<test>/` (`output_dir`), replacing `trace_dir` and `screenshot_dir`. `trace: :open`
  is gone: run `mix playwright.cli show-trace <path>`, which a failed test that keeps a trace prints.
  `trace: :on_first_retry` replaces the 0.19 README's `PW_TRACE=true mix test --failed` rerun:
  a test under `mix test --failed` is its first retry.
- **Context options:** `browser_context_opts` is `context_options`, in Playwright's forms
  (`extra_http_headers` as a map, `viewport: :null`). `browser_page_opts` is gone.
- Unknown launch and context options raise, e.g. `ignore_all_default_args` (use
  `ignore_default_args: true`). The `:android` and `:electron` browsers are removed.

## Per module and per test

`use PhoenixTest.Playwright.Case` passes its options to `use Playwright.Test`, except
`accept_dialogs` and `ecto_sandbox_stop_owner_delay` (module tags, as before) and ExUnit's.
An unknown option raises, so move other tags given there to `@moduletag`:

```diff
-use PhoenixTest.Playwright.Case, async: true, browser: :firefox, timeout: 60_000
+use PhoenixTest.Playwright.Case, async: true, browser_name: :firefox
+@moduletag timeout: 60_000
```

- `browser_launch_opts: [...]` is `launch_options: [...]`, which replaces the config's
  `launch_options` as a whole: repeat the ones you keep, such as `headless`. `slow_mo` and
  `executable_path` go into it too; drop `browser_launch_timeout` and `browser_pool`. Given as
  `use` options, they now raise as unknown. `headless` stays a `use` option, Playwright Test's own.
- `browser_context_opts: [locale: "de"]` is `locale: "de"` in the `use` options, or
  `@describetag Playwright.Test.use(locale: "de")` for a describe block, `@tag` for a test. A value a
  setup computes, such as a `storage_state`, goes to the second argument of
  `PhoenixTest.Playwright.Case.do_setup/2` (or the third of `new_session/3`).
- Run a module per browser with Playwright's projects:

  ```diff
   use PhoenixTest.Playwright.Case,
     parameterize: [
  -    %{browser_pool: :chromium},
  -    %{browser_pool: :firefox}
  +    Playwright.Test.parameters(name: "chromium", browser_name: :chromium),
  +    Playwright.Test.parameters(name: "firefox", browser_name: :firefox)
     ]
  ```

  The `name:` labels failures and keeps a snapshot baseline per browser.
- Record one test with `@tag Playwright.Test.use(trace: :on)` (or `screenshot:`, `video:`), a
  describe block with `@describetag`. A plain `@tag trace: ...` is ignored, with a warning.
- `browser`, `browser_launch_opts` and `browser_context_opts` raise as tags, in `parameterize:`, in
  the `use` options and in `config :phoenix_test, :playwright`, naming their replacement.

## Screenshots

- `assert_screenshot/3` resolves baselines as in Playwright Test, by default
  `test/<test file>-snapshots/<name>-<platform>.png`, and writes comparison output to
  `test-results/<test>/` instead of `__diff__/`. To keep 0.19's single directory:

  ```elixir
  config :playwright, :test, snapshot_dir: "test/snapshots", snapshot_path_template: "{snapshotDir}/{arg}{ext}"
  ```
- `assert_screenshot/3` takes no `snapshot_dir:`: `snapshot_dir` is config only. Put the
  subdirectory in the name instead, as in `assert_screenshot(conn, "admin/home.png")`.
- A missing baseline is written and fails the test at the end of its body, so CI catches a
  baseline nobody committed. `config :playwright, :test, update_snapshots: :missing` passes instead.
- Baselines must be `.png` or `.webp`, and `animations: "disabled"` and `scale: "css"` now apply:
  regenerate baselines captured with running animations or a device scale factor above 1.
- `screenshot/3` writes to the test's output dir.

## Behavior

- Browser contexts get Playwright Test's defaults: `locale: "en-US"` instead of `"en"`, and a
  1280x720 viewport. An app that picks its language from the request can render another one:
  set `locale` in `context_options`.
- A configured `user_agent` (in `context_options`, or a device's) gets the Ecto sandbox's metadata
  appended. In 0.19 it replaced the metadata.
- A `base_url` set through Playwright (`config :playwright, :test` or `Playwright.Test.use/1`) wins
  over phoenix_test's, for pages and for cookies without a `url` or `domain`.

## Code that calls Playwright

- `PlaywrightEx.Selector` is `PhoenixTest.Playwright.Selector`, with the same functions.
- `unwrap/2` passes `%{context: ..., page: ..., frame: ...}`, Playwright structs instead of guids
  (`context_id`, `page_id`, `frame_id`), and ignores the callback's result, so call the raising `!`
  functions there. Playwright's API follows the official client, see
  [From playwright.dev to Elixir](https://hexdocs.pm/playwright_ex/1.65.0-rc.4/api-conventions.html).
  Several workarounds have a function now:

  ```diff
  - |> unwrap(&PlaywrightEx.Frame.evaluate(&1.frame_id, expression: "axe.run()", timeout: 2_000))
  + |> evaluate("axe.run()")
  ```
- The ExUnit context holds `playwright_browser` (a `Playwright.Browser`) instead of `browser_id`.
- A `with_dialog/3` callback gets `dialog` (a `Playwright.Dialog`) instead of `guid`.
- `evaluate/2,3,4` return Playwright's values: JavaScript `null` is `:null` (was `nil`), and
  `undefined` is `nil`. `evaluate/3` takes no `is_function:` (function expressions are detected) and
  no `timeout:`.
- `clear_cookies/2` is gone: call `clear_cookies/1`, which takes no options.
- A custom `js_logger` implements `PhoenixTest.Playwright.JsLogger` (was `PlaywrightEx.JsLogger`), and
  `c:PhoenixTest.Playwright.JsLogger.log/3` gets a `Playwright.ConsoleMessage` or
  `Playwright.WebError` as its third argument instead of a map.
- `step/3` is `Playwright.Test.step`: steps nest in the trace's test steps.
- The `timeout/0` helper in test modules is gone.
