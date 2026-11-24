## Dev

- Use tool versions from `.tool-versions`; prefer `mise exec -- <command>` (for example `mise exec -- mix check`).
- If your shell is already activated by `mise`/`direnv`, plain `mix ...` commands are fine.
- Run targeted tests often while changing files.
- When feature is complete run `mix check`.
- When reviewing a change or fixing review findings, follow [Reviewing](CONTRIBUTING.md#reviewing).
- When feature is complete, update `CHANGELOG.md`. A change that breaks a 0.19 suite also gets a step in
  `docs/upgrading.md`, written as a change from 0.19 (not from the last release candidate).
- Always keep docs up to date (exdoc `@doc` + `@moduledoc`, `README.md`)

## Reference sources
- Skills built from the deps' usage rules are in `.agents/skills` (`.claude/skills` links there): `usage-rules` for looking up docs, `playwright` for the Playwright API.
- Dependencies' source is in `deps/` at the versions `mix.lock` pins, for example `deps/phoenix_test` and `deps/playwright` (the `playwright_ex` package).
- Playwright (`playwright_ex`) is a 1:1 port of the Playwright client. `mix phoenix_test_playwright.playwright_source` (part of `mix setup`) checks out Playwright's source at the version it pins into `tmp/playwright-<version>`. It is gitignored, so search it by path. Check Playwright-internal behavior, such as `internal:` selectors and their escaping, against it.

## phoenix_test upstream compatibility
- `test/phoenix_test/upstream/` is a mirror of upstream `phoenix_test` tests and is used as a compatibility suite.
- Do not add new Playwright-specific behavior tests under `test/phoenix_test/upstream/`.
- Put Playwright-only behavior tests in `test/phoenix_test/playwright_test.exs` (or other non-`upstream/` test files).
- `test/support/upstream/web_app/` is also copied from upstream and should be changed as little as possible.
- If you must change an upstream-mirrored file, keep the delta minimal and document why.
