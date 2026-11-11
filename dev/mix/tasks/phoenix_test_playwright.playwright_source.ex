defmodule Mix.Tasks.PhoenixTestPlaywright.PlaywrightSource do
  @shortdoc "Fetches the Playwright source of the driver version PlaywrightEx pins"
  @moduledoc """
  Clones Playwright's source at the tag of the pinned driver (`v<version>`, see
  `PlaywrightEx.Driver.version/0`) into gitignored `tmp/playwright-<version>`, unless that
  exists. The clone is shallow, blobless and sparse, checking out only `@paths`.

      mix phoenix_test_playwright.playwright_source
  """
  use Mix.Task

  @paths ~w(
    packages/playwright-core/src packages/injected/src packages/isomorphic packages/protocol
    packages/utils packages/playwright/src/matchers docs/src/api tests/page tests/library
  )

  @impl Mix.Task
  def run(_args) do
    version = PlaywrightEx.Driver.version()
    dir = "tmp/playwright-#{version}"

    if not File.dir?(dir) do
      # Into a temporary directory first, so an interrupted clone isn't taken for a finished one.
      tmp = dir <> ".tmp"
      File.rm_rf!(tmp)

      git!(
        ~w(clone --depth 1 --filter=blob:none --sparse --branch v#{version} https://github.com/microsoft/playwright #{tmp})
      )

      git!(["-C", tmp, "sparse-checkout", "set" | @paths])
      File.rename!(tmp, dir)
    end

    Mix.shell().info("Playwright #{version} source: #{dir}")
  end

  defp git!(args) do
    {output, status} = System.cmd("git", args, stderr_to_stdout: true)
    if status != 0, do: Mix.raise("git #{Enum.join(args, " ")} exited with #{status}:\n#{output}")
  end
end
