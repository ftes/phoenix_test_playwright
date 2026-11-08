defmodule PhoenixTest.Playwright.Supervisor do
  @moduledoc """
  Supervises the Playwright driver and browser pools.

  Runs a local Node.js Playwright driver. Browsers are launched by the driver, or,
  when `ws_endpoint` is configured, the driver connects to a remote Playwright server.
  """

  use Supervisor

  alias PhoenixTest.Playwright.Config

  # Takes no config. The `[]` is what `child_spec/1` passes.
  def start_link([] \\ []) do
    # Host apps usually depend on this library with `runtime: false`, which leaves it to us.
    {:ok, _} = Application.ensure_all_started(:playwright_ex)
    Supervisor.start_link(__MODULE__, Config.global(), name: __MODULE__)
  end

  @impl true
  def init(config) do
    config = Config.validate!(config)

    children = [
      {PlaywrightEx.Supervisor, playwright_opts(config)},
      PhoenixTest.Playwright.DriverWatcher,
      PhoenixTest.Playwright.BrowserPoolSupervisor
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  # Without an executable, PlaywrightEx uses its own driver, so `assets_dir` isn't needed.
  defp playwright_opts(config) do
    if config[:ws_endpoint], do: [], else: [executable: Config.executable()]
  end
end
