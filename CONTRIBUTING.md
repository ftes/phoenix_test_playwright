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

## Releasing

The script needs a jj working copy colocated with git, `gh` logged in as a repo admin (to push
`main` past its ruleset and create the tag), and `curl` and `elixir` on the PATH.

1. For the first non-RC release, merge the RC sections into `## [Unreleased]` and drop the `RC
   only:` entries; the script refuses while they remain.
2. `scripts/release --dry-run <version>` runs the checks (an empty `@` on `main@origin` as last
   fetched, an `## [Unreleased]` with entries, a new tag and a greater version) and prints the
   edits.
3. `scripts/release <version>` commits "Release <version>" (the version, the install line in
   `README.md` and the dated changelog heading) and "Start the next release", pushes `main` and
   tags the first commit. It fetches first and checks again. `RELEASE_REMOTE` names another remote
   than `origin`.
4. The tag runs CI (`elixir.yml`) on the tagged commit; once every job passed, its publish job
   stages the release on Hex. Approve it on hex.pm; the job then creates the GitHub release.

It runs locally, not as a workflow: only an admin can push to `main` past its ruleset, and a tag
pushed with `GITHUB_TOKEN` starts no workflow. `scripts/release` runs ftes/ci's
`release/release.exs` at a pinned commit (Renovate bumps it, and CI's `scripts/release --check`
tests each bump against this repo); this repo's settings are `scripts/release_config.exs`.

## Playwright internals

Playwright's implementation is split between a **client** (Node.js API) and a **server** (browser protocol layer). The [Playwright docs](https://playwright.dev/docs/intro) describe the public API but don't reflect this split. When reading Playwright source code, it can help to look at the TypeScript sources directly: [client](https://github.com/microsoft/playwright/tree/main/packages/playwright-core/src/client) and [server](https://github.com/microsoft/playwright/tree/main/packages/playwright-core/src/server) (locally under `package/lib/` in `Playwright.Driver.install_dir/0`).
