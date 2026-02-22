[![Hex.pm Version](https://img.shields.io/hexpm/v/phoenix_test_playwright)](https://hex.pm/packages/phoenix_test_playwright)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/phoenix_test_playwright/)
[![License](https://img.shields.io/hexpm/l/phoenix_test_playwright.svg)](https://github.com/ftes/phoenix_test_playwright/blob/main/LICENSE.md)
[![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/ftes/phoenix_test_playwright/elixir.yml)](https://github.com/ftes/phoenix_test_playwright/actions)

# PhoenixTestPlaywright

Execute PhoenixTest cases in an actual browser via Playwright.

Please [get in touch](https://ftes.de) with feedback of any shape and size.

Enjoy!

Freddy.

**Documentation:** [hexdocs.pm](https://hexdocs.pm/phoenix_test_playwright/)

**Example:** [ftes/phoenix_test_playwright_example](https://github.com/ftes/phoenix_test_playwright_example)

**Standalone Playwright client:** [ftes/playwright_ex](https://github.com/ftes/playwright_ex)

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
