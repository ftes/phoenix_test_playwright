# Dependency updates

Install the [Renovate GitHub App](https://github.com/apps/renovate) for
`ftes/phoenix_test_playwright` to activate `renovate.json`. Renovate discovers Mix and npm
projects, GitHub Actions, and all Elixir, Erlang and Node pins in `.tool-versions`.
It also updates pnpm wherever configured, grouping its package-manager pin with
the toolchain updates.

Update PRs are scheduled for Monday 00:00–06:59 Europe/Berlin, with a two-day
minimum release age where timestamps are available (three days for npm via the
best-practices preset). Patch, minor and major
updates are eligible; automerge is disabled. GitHub Actions retain full commit
SHA pins with version comments. CI reads `.tool-versions` directly.

Elixir retains its OTP build suffix. An Erlang major upgrade may require choosing
a compatible Elixir build before the PR passes CI. Minimum Node engine constraints
remain a manual compatibility decision.

Use the Renovate Dependency Dashboard issue or the
[Mend portal](https://developer.mend.io/github/ftes/phoenix_test_playwright) to inspect
updates and job logs. Keep GitHub's Dependabot security alerts enabled separately;
Renovate replaces Dependabot's version-update configuration.

Renovate extends `config:best-practices`, including action/container digest pins,
development-dependency pins and weekly lockfile maintenance. Mix overrides the
preset's development-dependency pinning with `in-range-only`: `mix.exs` support
ranges stay unchanged, while weekly maintenance lets Mix resolve the newest
allowed versions in `mix.lock`. Out-of-range Mix upgrades require a manual
constraint change. Other dependency ranges retain `replace`, except where the
preset pins development dependencies.

Renovate generates Mix lockfiles with OTP 29 and Elixir 1.20.4, configured via
`constraints`. Its Mix worker otherwise defaults to OTP 26, which cannot run
Elixir 1.20. These worker constraints do not restrict proposed toolchain updates;
review them when adopting a newer Elixir/OTP release line.
