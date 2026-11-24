# This repo's settings for ftes/ci's release script (scripts/release fetches it); its header
# documents each key.
defmodule ReleaseScript.Config do
  @moduledoc false

  def config do
    %{
      repo: "ftes/phoenix_test_playwright",
      # `RELEASE_REMOTE` names another remote than origin.
      remote: System.get_env("RELEASE_REMOTE", "origin"),
      branch: "main",
      # Its publish job releases a pushed `v*` tag once the tests passed.
      workflow: "elixir.yml",
      hex_package: "phoenix_test_playwright",
      # Not docs/upgrading.md: its requirement is the guide's target, not the latest release.
      snippets: [{"README.md", ~r/\{:phoenix_test_playwright, "~> ([^"]+)"/}],
      driver_line: false,
      driver_minor: false,
      minor_requirement: true,
      changelog: %{
        unreleased: "## [Unreleased]",
        version_prefix: "## [",
        version_suffix: "]",
        date_separator: " ",
        reopen_prereleases: false,
        rc_only: "RC only:"
      }
    }
  end
end
