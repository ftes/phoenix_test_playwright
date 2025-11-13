defmodule PhoenixTest.Playwright.Supervisor do
  @moduledoc false

  use Supervisor

  alias PhoenixTest.Playwright.BrowserPool
  alias PhoenixTest.Playwright.Config
  alias PhoenixTest.Playwright.Connection

  def start_link do
    Supervisor.start_link(__MODULE__, :no_init_arg, name: __MODULE__)
  end

  @impl true
  def init(:no_init_arg) do
    pools = Config.global(:browser_pools)
    children = [Connection | Enum.map(pools, &Supervisor.child_spec({BrowserPool, &1}, id: &1))]
    Supervisor.init(children, strategy: :one_for_one)
  end
end
