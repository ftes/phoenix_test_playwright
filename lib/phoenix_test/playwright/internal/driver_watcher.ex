defmodule PhoenixTest.Playwright.DriverWatcher do
  @moduledoc false
  # Selector engines are registered per driver. PlaywrightEx restarts a crashed driver on its
  # own, so this stops with the driver: the `rest_for_one` supervisor then registers the engines
  # again. Only for the `ws_endpoint` driver: `PlaywrightEx.Test.BrowserPool` runs `on_start`.

  use GenServer

  alias PhoenixTest.Playwright.Selector.Engines

  def start_link(driver), do: GenServer.start_link(__MODULE__, driver)

  # Blocks until registered, so that the first browser context can use the engines.
  @impl GenServer
  def init(driver) do
    # Blocks while the driver restarts, so the monitor below finds it.
    playwright = PlaywrightEx.playwright(driver)
    # Before registering: a driver replaced from here on must not go unnoticed.
    ref = Process.monitor(PlaywrightEx.Supervisor.out_of_process(driver))
    Engines.register(playwright)
    {:ok, ref}
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, _pid, _reason}, ref), do: {:stop, {:shutdown, :driver_down}, ref}
end
