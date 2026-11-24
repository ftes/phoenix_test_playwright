# Playwright usage rules

This library (`Playwright`, Hex package `playwright_ex`) is a 1:1 Elixir port of the Playwright client. Its API is generated from upstream's
docs, so playwright.dev applies; the Python docs are the closest read.

**For no timeout, pass `timeout: :infinity`.** Unlike Elixir's convention, where `0` means don't wait (`receive ... after 0`), `timeout: 0` here means no timeout, as in Playwright JS: never use it for an immediate check.

## Setup

- Depend on `{:playwright, "~> 1.65.0-rc.4", hex: :playwright_ex}` (the README has the current version). `hex: :playwright_ex` is required. Versions are Playwright's major.minor with our own patch, so `~> 1.65.0` takes our fixes for Playwright 1.65. If only tests use it, prefer `only: [:dev, :test]` to `only: :test`, so its mix tasks work in `:dev`.
- The app is `:playwright`, the modules `Playwright.*`. The Hex package `playwright` (hexdocs.pm/playwright) is another Elixir library, playwright-elixir, with another API: don't use its docs or examples (`Playwright.launch(:chromium)`, `Playwright.Page.click(page, selector)`). This library's docs are at hexdocs.pm/playwright_ex.
- `mix playwright.install` installs the pinned driver (Node.js and `playwright-core`) and browsers. Do not add npm `playwright`.
- `mix playwright.install chromium --with-deps` installs one browser and its system packages on Linux CI. `--no-browsers` installs only the driver, for a browser launched with `:executable_path` or `:channel`. Run the task again after upgrading the dependency. In CI, set `MIX_ENV: test` for the whole job, so `deps.get`, the install and `mix test` share one build.
- Tests use `Playwright.Test` (see "Testing with Playwright.Test"). It starts its drivers on the first test and stops them after the suite, so `test_helper.exs` needs only `ExUnit.start()`. Don't start a `Playwright.Supervisor` for the tests' browsers. A global setup in `test_helper.exs` (upstream's `globalSetup`, say a login saved with `storage_state!(context, path: ...)` for config `storage_state: path`) may start a named one and stop it before `ExUnit.start()`, at the cost of one more driver start.
- Apps, scripts and hand-rolled test setups start one driver: `{Playwright.Supervisor, name: MyApp.PlaywrightDriver}` in a supervision tree, read with `Playwright.instance(MyApp.PlaywrightDriver)`. Without `:name` it registers as `Playwright`, read with `Playwright.instance()`; in a script or `test_helper.exs`, `{:ok, _} = Playwright.Supervisor.start_link()`, and `Supervisor.stop(Playwright)` at the end (`ExUnit.after_suite/1` in tests).
- Don't alias a module of your own named `Playwright` (`alias MyApp.Playwright`) where you use this library: `Playwright.Page` and `Playwright.instance()` then silently resolve to `MyApp.Playwright.Page` and `MyApp.Playwright.instance()`. Call yours in full or `import` it, or alias it `as: MyPlaywright`. In a sorted alias list, `alias MyApp.Playwright` comes before `alias Playwright.Page`, which then expands to `MyApp.Playwright.Page`: write `alias Elixir.Playwright.Page` there.
- Outside `Playwright.Test`, share one browser, give each user its own context, and close what you open, for example `on_exit(fn -> BrowserContext.close(context) end)`. A browser or context does not close when the process that created it exits.

```elixir
# A script, after Playwright.Supervisor.start_link()
alias Playwright.{Browser, BrowserContext, BrowserType, Expect, Locator, Page}

browser = Playwright.instance() |> Playwright.chromium() |> BrowserType.launch!()
context = Browser.new_context!(browser, base_url: "http://localhost:4000")
page = BrowserContext.new_page!(context)

Page.goto!(page, "/sign-up")
Page.get_by_label(page, "Email") |> Locator.fill!("ada@example.com")
Page.get_by_role(page, :button, name: "Sign up") |> Locator.click!()
Expect.to_have_text!(Page.get_by_role(page, :status), "Welcome")
```

## API shape

- Use the generated facade: `Playwright.Page`, `Locator`, `BrowserContext`, `Expect` and so on. `Playwright.Client.*` and `Playwright.Runtime.*` are internal.
- A JS method is a function taking the object first, in snake_case. Properties are functions too (`Page.keyboard(page)`). Predicates keep Python's names: `Locator.is_visible!/2`, not `visible?`.
- A call JS awaits has two forms. `name` returns `{:ok, value}`, `:ok` for a void call, or `{:error, exception}`. `name!` returns the value, `:ok` for a void call, or raises.
- Use bang forms in scripts and tests, tuple forms where failure is an expected outcome.
- A call JS does not await returns a plain value and has no bang form: `Page.url/1`, `Page.locator/3`, `Page.get_by_role/3`, `Locator.filter/2`.
- Options come last, as a keyword list or map with snake_case keys: `Page.screenshot!(page, path: "a.png", full_page: true)`. Unknown keys raise `ArgumentError` from both forms.
- Nested option values and object arguments are maps with the JS keys, unknown ones raise too: `viewport: %{width: 1280, height: 720}`, `add_cookies!(context, [%{name: "a", value: "b", url: url, httpOnly: true}])`.
- String enums are atoms (`:no_preference`). `nil` is JS `undefined`, `:null` is JS `null`, also in `evaluate` results. A call returning JS `X | null` returns `nil` (`Locator.get_attribute!/2` of a missing attribute).
- `JSON.encode!/1` turns `:null` into `"null"`: pass such terms to the page as an `evaluate` argument (`:null` arrives as `null`), and `JSON.stringify` there if it needs a string.
- Strings are literal text or URL globs; use `~r//` for a pattern.

## Locators and assertions

- Follow Playwright's locator priority: `Page.get_by_role/3` with `name:`, then `get_by_label`, `get_by_placeholder`, `get_by_text` (non-interactive elements), `get_by_alt_text` or `get_by_title`, `get_by_test_id`; `Page.locator/3` with CSS or XPath last, never by CSS classes or DOM structure. If no user-facing locator fits, consider fixing the markup (a field without a `<label>`, a button without an accessible name). Roles are atoms (`:button`); one the typespec lacks is a string (`"mark"`).
- Narrow by chaining and filtering: `Locator` has the same `get_by_*` functions, and `Locator.filter/2` takes `has_text:`, `has:`, `has_not_text:` and `has_not:`: `Page.get_by_role(page, :listitem) |> Locator.filter(has_text: "Product 2") |> Locator.get_by_role(:button, name: "Add to cart")`.
- Locators are lazy and strict: an action on a locator matching several elements fails. Use `Locator.first/1`, `last/1` or `nth/2` only when order is what tells identical elements apart.
- Assert with `Playwright.Expect`, which retries until the timeout: `Expect.to_be_visible!(Page.get_by_text(page, "Welcome"))`, `Expect.to_have_url!(page, ~r"/dashboard$")`. `assert Locator.is_visible!(l)` or `assert Locator.text_content!(l) == "x"` reads once and races the page.
- Negate with `Expect.not_to_be_visible!(l)` or `l |> Expect.not_() |> Expect.to_be_visible!()`.
- Matchers return `:ok` or `{:error, %Playwright.ExpectError{}}`; the bang forms raise the error, which fails an ExUnit test.

## Timeouts and `Expect` configuration

Actions and navigations wait 30 seconds, except in a `Playwright.Test` test, where only the test's timeout bounds them (see below). Lower that per context with `BrowserContext.set_default_timeout/2` and `set_default_navigation_timeout/2` rather than a `timeout:` on every call. Matchers wait 5 seconds, also in tests, and are configured as in `playwright.config.ts`, by the `expect` block of the `:test` config (read also without `Playwright.Test`):

```elixir
# config/test.exs
config :playwright, :test, expect: [timeout: 10_000], update_snapshots: :missing
```

- `expect`'s keys are `:timeout`, `:to_have_screenshot`, `:to_match_aria_snapshot` and `:to_pass`. Next to it, `update_snapshots` (`:all`, `:changed`, `:missing`, `:none`, `:default`) and `ignore_snapshots` are `:test` keys, as upstream's top-level `updateSnapshots` and `ignoreSnapshots`. Other keys raise `ArgumentError`.
- A matcher's keys are snake_case, as its options: `to_have_screenshot: [max_diff_pixels: 10, path_template: "..."]`, `to_match_aria_snapshot: [children: :equal]`, `to_pass: [timeout: 10_000, intervals: [1000]]`. JS keys (`maxDiffPixels`) raise.
- A matcher's own `timeout:` wins.
- An inline aria snapshot cannot be written into test source. Where a rebaseline applies, the matcher fails with the new snapshot in its message.

## Testing with Playwright.Test

ExUnit is the runner. `Playwright.Test` adds Playwright Test's per-test machinery: browsers from a pool, context defaults, traces, screenshots, videos, steps and snapshot paths. There is no `@playwright/test` and no fixture injection.

```elixir
# config/test.exs
config :playwright, :test,
  base_url: "http://localhost:4000",
  trace: :retain_on_failure,
  screenshot: :only_on_failure

defmodule MyApp.SignUpTest do
  use Playwright.Case, async: true

  test "signs up", %{page: page} do
    Page.goto!(page, "/sign-up")
    Expect.to_have_title!(page, "Sign up")
  end
end
```

- `use Playwright.Case` gives the module a `browser` and its `browser_name` (in `setup_all`'s context and the test's) and each test a fresh `context` and `page`, and aliases `Browser`, `BrowserContext`, `Expect`, `Keyboard`, `Locator`, `Mouse`, `Page`, `Test` and `Test.BrowserPool`. In a case template, `use Playwright.Case` inside `using` and add your `setup` after it.
- Upstream's fixtures are functions: `browser` is `BrowserPool.browser/1`, `testInfo` is `Playwright.Test.info/0`, `browserName` is `browser_name` in `Playwright.Case`'s context. `beforeAll` is `setup_all`, `afterEach` an `on_exit`. Upstream's `request` fixture is `APIRequest.new_context!(Playwright.request(BrowserPool.playwright(browser)))`, not `Page.request/1` (which shares the page's cookies).
- Set `test.use({...})` options by level, values known at compile time, never functions: config; project `parameterize: [Playwright.Test.parameters([name: "Mobile Safari"] ++ Playwright.device("iPhone 13"))]` (in full: the `Test` alias comes with the `use`; `name:` labels it in failure output and annotations and fills `{projectName}`: name each project of a module with several, as an unnamed one has no label); file `use Playwright.Case, locale: "de-DE", trace: :on`; `test.describe` `@describetag Test.use(...)`; one test `@tag Test.use(...)`. The context options are options of their own with `Browser.new_context/2`'s names; `context_options` only for the rest (`record_har`, ...). `Playwright.Test`'s moduledoc has which option each level takes and how `nil` falls back.
- Don't write plain tags named like options: `@tag trace: :on` sets nothing, silently. Write `@tag Test.use(trace: :on)`; find leftovers with `rg "@(module|describe)?tag[ (\[][^(]*\b(trace|screenshot|video):"`.
- Don't put `browser_name`, `headless`, `channel`, `launch_options`, `connect_options` or a device in a `@describetag` or `@tag` `Test.use(...)`: they are the worker's, and the module raises when it compiles a `test` under it, as Playwright Test's `test.use` in a describe. Set them in the module's `use` or `@moduletag Test.use(...)`s (merged, the later winning per option; for all its tests), a project or the config; a browser or a device per run is a project in `parameterize:`; a device's emulation alone in a describe is `Keyword.delete(Playwright.device("Pixel 7"), :default_browser_type)`.
- Read a test's resolved options with `Playwright.Test.info().use`, with Access (`use[:base_url]`), not from `Test.config()`. A library that passes options in a call merges into them, as a call's options replace them as a whole: `extra_http_headers: Map.merge(Test.info().use[:extra_http_headers] || %{}, headers)`. Outside a test or `setup_all`: `if Test.in_registered_scope?(), do: Test.info().use, else: Test.config()`.
- `Playwright.Test.info().project` is the module's `Playwright.Test.Project` (`parameterize:` with `Playwright.Test.parameters/1`), else the default project (`name: nil`). Its `use` is the config's options with the project's over them (`context_options` and `launch_options` as given); a test's resolved options, every level and the defaults included, are `info().use`.
- `Playwright.Test.info().deadline` is monotonic milliseconds (compare with `System.monotonic_time(:millisecond)`) by which the test must be done: after it, the test's contexts are closed and Playwright calls fail; `:infinity` without a test timeout. A library that waits or retries on its own stops by it.
- Use `Playwright.device("iPhone 13")` (raises for an unknown name), not `Playwright.devices()["iPhone 13"]` (`nil` falls back silently). Override a device's option with `++`: a later key wins, as in JS's spread (`Playwright.device("iPhone 13") ++ [locale: "de-DE"]`). Not in `config/config.exs` or `config/test.exs` (not compiled yet): for a suite-wide device use `config/runtime.exs` inside `if config_env() == :test`.
- In a case template, put its own `use Playwright.Test, ...` lines before the forwarded `use Playwright.Case, unquote(opts)` (later `use`s win per option), and pop its own options first.
- Prefer many small `async: true` modules: a module's tests run in sequence, and `BrowserPool` gives each module one worker (at most `workers` at once), replaced after a failure. Register selectors per driver with `on_start: &MyApp.Selectors.register/1`.
- Don't add a `timeout:` per call: in a test only ExUnit's timeout (60 s, `@tag timeout:`) bounds actions and navigations; set `action_timeout`/`navigation_timeout` in config to fail sooner.
- Rerun failures only on exit status 2, without `--partitions`, and call `mix test` directly (an alias through `mix cmd` turns 2 into 1): `mix test --partitions 4 || { [ $? -eq 2 ] && mix test --failed; }`. `trace: :on_first_retry` then traces only the rerun. Pass `Playwright.Test.GitHubFormatter` to both runs (upstream annotates every attempt; a test passing on the rerun is flaky), and upload `test-results` with `if: ${{ !cancelled() }}`, not `failure()`, so a job the rerun turned green keeps the first run's files.
- On Elixir 1.20 and earlier, `mix test --failed` loses a failure in a `parameterize:` module when another parameter set (a project, or your own parameter list) passes the same test (the manifest keys tests by module and name, last result wins), and a `setup_all` `on_exit` failure after passing tests: run one project per `mix test`, e.g. a CI matrix over the project env var, each job running `mix test || { [ $? -eq 2 ] && mix test --failed; }` (Retries in guides/test-artifacts.md). That avoids only the cross-project case; failures across own parameter lists in one run and the `on_exit` failure can still be lost, and an empty retry then passes. <!-- remove with Elixir 1.21: ftes/playwright_ex#319 -->
- A failed test writes `error-context.md` (errors, source, an aria snapshot) to `test-results/<test>/`: read it first. Open traces with `mix playwright.cli show-trace <path>`.
- `Playwright.Test.step "log in" do ... end` is `test.step`; pass `box: true` in helpers. A `describe.serial` becomes one test with a step per test.
- `assert` and `refute` are steps too (`Expect "assert"` in the trace): `use Playwright.Test` imports `Playwright.Test.Assertions`. Don't `import ExUnit.Assertions` after the `use` (an ambiguous `assert`); a helper module (no `use Playwright.Test`) needs `import Playwright.Test.Assertions` (plus `import ExUnit.Assertions, except: [assert: 1, assert: 2, refute: 1, refute: 2]` if it imports that), else its passed asserts silently leave no step. A library with its own `assert/2` excludes exactly the arities it defines (`import Playwright.Test.Assertions, except: [assert: 2]`), and its own `refute/2` must also take ExUnit's `refute(value, expr: ...)` from `refute match?` (delegate it to `Playwright.Test.Assertions.refute/2`); `Playwright.Test.Assertions` in `__CALLER__.macros` tells whether a module has them. Opt out with `use Playwright.Test, assert_steps: false`, or `config :playwright, :test, assert_steps: false` in `config/test.exs` (compile time, not `runtime.exs`).
- Commit written snapshots: a missing one is written to `<test file>-snapshots/` and fails the test. In a `:dialog` listener, accept or dismiss before asserting: a handler's or listener's error stops the test at once.
- Porting traps: an `Expect.poll!` callback that raises fails at once (`Enum.at(list, 0)`, not `hd/1`, while the list can be empty); `add_init_script` with a function's source and no argument only defines it (`"(#{fun})()"`).
- Details: the [testing guides](https://hexdocs.pm/playwright_ex/testing-with-exunit.html) and `Playwright.Test`.

## Configuration

- There is no `playwright.config.ts`, `package.json` or npm `playwright`/`@playwright/test`. Configure in Elixir config: `config :playwright, :test` is `playwright.config.ts` (the runner's keys, and the matchers' `expect`, `update_snapshots` and `ignore_snapshots`), the driver goes under `config :playwright, :driver`. Other `config :playwright` keys raise at startup, as do unknown keys in these. Values pass as given, as upstream's, except those upstream checks, which raise too: `workers`, `preserve_output`, `output_dir`, `browser_name`, `on_start`, `report_slow_tests`, `update_snapshots`, `ignore_snapshots`, `expect`'s `to_have_screenshot` `type` and the context options (as `Browser.new_context/2` checks them). An unknown artifact mode records nothing.
- `config :playwright, :test` keys: `browser_name` (`:chromium`), `headless` and `channel` (over `launch_options`'), `launch_options`, `connect_options` (`[ws_endpoint: _, ...]`), `driver`, `on_start`, `workers` (half the schedulers), the context options (`base_url`, `locale`, `storage_state`, ...) and `context_options` for the rest, `default_browser_type`, `action_timeout`, `navigation_timeout`, `trace`, `screenshot`, `video`, `output_dir` (`"test-results"`), `preserve_output` (`:always`, `:failures_only`, `:never`), `snapshot_dir`, `snapshot_path_template`, `test_id_attribute` (`"data-testid"`), `report_slow_tests` (`[max: 5, threshold: 300_000]`, `false` for none, `Playwright.Test.GitHubFormatter`'s), `assert_steps` (`true`, read at compile time), `expect` (the matchers', above), `update_snapshots` (`:default`), `ignore_snapshots` (`false`). The test id attribute is global to the VM: set it here, not per module.
- No option has an environment variable, and Playwright Test's (`PLAYWRIGHT_TEST_BASE_URL`, `PW_TEST_CONNECT_WS_ENDPOINT`) are not read. Read the ones you want in config: `base_url: System.get_env("BASE_URL", "http://localhost:4000")`. The library reads only those upstream's client and reporters read (such as `PWDEBUG=1`, `PWDEBUGIMPL`, `GITHUB_WORKSPACE`), `HTTPS_PROXY` (or `https_proxy`) for the driver download and, on Windows, `PROCESSOR_ARCHITECTURE` for its platform; the driver and its CLI read theirs (`DEBUG=pw:api`, `PLAYWRIGHT_BROWSERS_PATH`).
- Driver settings are `config :playwright, :driver` with `cache_dir:`, `executable:` (an npm-managed `playwright` CLI) and `node:` (a Node.js binary). Put them in `config/config.exs`, not `config/test.exs` or `config/runtime.exs`: `mix playwright.install` runs in `:dev` unless `MIX_ENV` says otherwise and doesn't compile the project, so it sees only `config/config.exs` and what it imports. Take an env var there: `if dir = System.get_env("PLAYWRIGHT_CACHE_DIR"), do: config(:playwright, :driver, cache_dir: dir)`. The `:test` config's `driver:` takes only `env:`, the pooled drivers' environment.

## Events and concurrency

- Start a wait before the action that triggers it. Use `Page.expect_download!(page, fn -> ... end)`, or `expect_popup!`, `expect_request!`, `expect_response!`, `expect_console_message!`, `expect_event!`.
- Or start `promise = Page.wait_for_event(page, :download)`, act, then `Playwright.Promise.await!(promise)`. `Page.wait_for_event!/3` awaits at once and misses what the code before it triggered.
- Your own check-then-wait can miss an event. Start the wait, read the state, then await the wait or call `Playwright.Promise.free/1`. The client's own waits and matchers already do this.
- `on/3`, `once/3` and `off/3` take a listener that runs in its own process. The connection waits for it to return or await a Playwright call before dispatching the next message.
- Keep listeners short. `Process.sleep/1`, `receive`, HTTP or a busy `GenServer.call` in a listener stalls every page on the connection. Send the work elsewhere:

```elixir
owner = self()
Page.on(page, :console, fn msg -> send(owner, {:console, ConsoleMessage.text(msg)}) end)
```

- A listener may call Playwright, as a `:dialog` listener calls `Dialog.accept!/1`. Dialogs without a listener are dismissed; with a listener, it must accept or dismiss them.
- Any process can await a promise, while the process that started the wait is alive. Calls from many processes overlap freely.

## Going beyond the facade

- `Page.evaluate!/3` and `Locator.evaluate!/3` take JS source, an expression or a function receiving the optional argument. Use them for what the API does not expose, not to click or read what a locator can.
- Debug with traces (`BrowserContext.tracing/1`, `Tracing.start!/2`, `Tracing.stop!/2`), viewed by `mix playwright.cli show-trace trace.zip`. In tests, use the `trace` mode instead.
