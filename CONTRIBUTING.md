# Contributing

To run the tests locally, you'll need to:

1. Check out the repo
2. Run `mix setup`. This will take care of setting up your dependencies, installing the Playwright driver and browsers, and compiling the assets.
3. Run `mix test` or, for a more thorough check that matches what we test in CI, run `mix check`. CI also runs `MIX_ENV=dev mix docs --warnings-as-errors`.

The compatibility floor is Elixir 1.18 on OTP 27 (`.tool-versions.oldest` and `mix.lock.oldest`,
which CI's oldest lane uses).
`mix.lock.oldest` locks every direct runtime dependency at its floor, the lowest version its
requirement in `mix.exs` accepts, which `DependencyFloorsTest` checks. To move one, copy
`.tool-versions.oldest` to `.tool-versions` and `mix.lock.oldest` to `mix.lock`, require
exactly the new floor, run `mix deps.update <dep>`, restore the requirement, and keep the
lock as `mix.lock.oldest` once `mix deps.get` leaves it unchanged from an empty `deps/`,
as CI runs it. Then restore `.tool-versions` and `mix.lock`.
Renovate never updates `mix.lock.oldest`. When `mix.exs` no longer accepts what it locks (a raised
floor, or a dev dependency's new major), CI's oldest lane fails at setup with "deps.get changed
mix.lock.oldest"; update the lock as above.

## Conventions

- **Follows PhoenixTest API.** Only add new public functions when strictly necessary for browser-specific interaction (e.g., screenshots, JS evaluation).
- **Keep upstream tests mirrored.** Files under `test/phoenix_test/upstream/` are mirrored from [phoenix_test](https://github.com/germsvel/phoenix_test). Limit local changes to compatibility skip tags; Playwright-specific behavior tests go in `test/phoenix_test/playwright_test.exs` or other files outside `upstream/`.

## Reviewing

Besides correctness, review a change for simplicity, consistency and scope. This applies to
human and agent reviews alike.

- Prefer the change that removes or shares code over one that adds a parallel path; logic several
  modules repeat belongs in one place.
- Follow how the codebase already does the same thing. A new pattern needs a reason.
- A PR fixes its issue. Edge cases and gaps that predate it are follow-ups: note them
  instead of adding code for them in the PR.

## Playwright internals

Playwright's implementation is split between a **client** (Node.js API) and a **server** (browser protocol layer). The [Playwright docs](https://playwright.dev/docs/intro) describe the public API but don't reflect this split. When reading Playwright source code, it can help to look at the TypeScript sources directly: [client](https://github.com/microsoft/playwright/tree/main/packages/playwright-core/src/client) and [server](https://github.com/microsoft/playwright/tree/main/packages/playwright-core/src/server) (locally under `package/lib/` in `Playwright.Driver.install_dir/0`).
