## Dev

- Use tool versions from `.tool-versions`; prefer `mise exec -- <command>` (for example `mise exec -- mix check`).
- If your shell is already activated by `mise`/`direnv`, plain `mix ...` commands are fine.
- Run targeted tests often while changing files.
- When feature is complete run `mix check`.
- When feature is complete, update `CHANGELOG.md`.
- Always keep docs up to date (exdoc `@doc` + `@moduledoc`, `README.md`)
- If you changed browser transport / websocket behavior, also run `mix test.websocket`.

## Reference sources
- Dependencies' source is in `deps/` at the versions `mix.lock` pins, for example `deps/phoenix_test` and `deps/playwright_ex`.
- PlaywrightEx is a 1:1 port of the Playwright client. `mix phoenix_test_playwright.playwright_source` (part of `mix setup`) checks out Playwright's source at the version PlaywrightEx pins into `tmp/playwright-<version>`. It is gitignored, so search it by path. Check Playwright-internal behavior, such as `internal:` selectors and their escaping, against it.

## phoenix_test upstream compatibility
- `test/phoenix_test/upstream/` is a mirror of upstream `phoenix_test` tests and is used as a compatibility suite.
- Do not add new Playwright-specific behavior tests under `test/phoenix_test/upstream/`.
- Put Playwright-only behavior tests in `test/phoenix_test/playwright_test.exs` (or other non-`upstream/` test files).
- `test/support/upstream/web_app/` is also copied from upstream and should be changed as little as possible.
- If you must change an upstream-mirrored file, keep the delta minimal and document why.

<!-- usage-rules-start -->
<!-- usage_rules-start -->
## usage_rules usage
_A config-driven dev tool for Elixir projects to manage AGENTS.md files and agent skills from dependencies_

## Using Usage Rules

Many packages have usage rules, which you should *thoroughly* consult before taking any
action. These usage rules contain guidelines and rules *directly from the package authors*.
They are your best source of knowledge for making decisions.

## Modules & functions in the current app and dependencies

When looking for docs for modules & functions that are dependencies of the current project,
or for Elixir itself, use `mix usage_rules.docs`

```
# Search a whole module
mix usage_rules.docs Enum

# Search a specific function
mix usage_rules.docs Enum.zip

# Search a specific function & arity
mix usage_rules.docs Enum.zip/1
```


## Searching Documentation

You should also consult the documentation of any tools you are using, early and often. The best 
way to accomplish this is to use the `usage_rules.search_docs` mix task. Once you have
found what you are looking for, use the links in the search results to get more detail. For example:

```
# Search docs for all packages in the current application, including Elixir
mix usage_rules.search_docs Enum.zip

# Search docs for specific packages
mix usage_rules.search_docs Req.get -p req

# Search docs for multi-word queries
mix usage_rules.search_docs "making requests" -p req

# Search only in titles (useful for finding specific functions/modules)
mix usage_rules.search_docs "Enum.zip" --query-by title
```


<!-- usage_rules-end -->
<!-- playwright_ex-start -->
## playwright_ex usage
_Elixir client for Playwright: a port of the official JavaScript client._

[playwright_ex usage rules](deps/playwright_ex/usage-rules.md)
<!-- playwright_ex-end -->
<!-- usage-rules-end -->
