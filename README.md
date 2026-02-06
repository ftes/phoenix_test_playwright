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
