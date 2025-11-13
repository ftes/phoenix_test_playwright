defmodule PhoenixTest.Playwright.Supervisor do
  @moduledoc false

  alias PhoenixTest.Playwright.BrowserPool
  alias PhoenixTest.Playwright.Config

  def start_link do
    pools = Config.global(:browser_pools)
    Supervisor.start_link(Enum.map(pools, &child_spec/1), strategy: :one_for_one)
  end

  defp child_spec(opts) do
    Supervisor.child_spec({BrowserPool, opts}, id: Keyword.fetch!(opts, :id))
  end
end
