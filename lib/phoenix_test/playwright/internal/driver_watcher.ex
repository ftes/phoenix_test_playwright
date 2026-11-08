defmodule PhoenixTest.Playwright.DriverWatcher do
  @moduledoc false
  # Selector engines are registered per driver, and browsers die with it. PlaywrightEx restarts a
  # crashed driver on its own, so this stops with the driver: the `rest_for_one` supervisor then
  # registers the engines again and replaces the browser pools.

  use GenServer

  alias PhoenixTest.Playwright.Selector.Engines
  alias PlaywrightEx.Playwright
  alias PlaywrightEx.Selectors

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil)

  # Blocks until registered, so that the first browser context can use the engines.
  @impl GenServer
  def init(nil) do
    # Blocks while the driver restarts, so the monitor below finds it.
    selectors = Playwright.selectors(PlaywrightEx.playwright())
    # Before registering: a driver replaced from here on must not go unnoticed.
    ref = Process.monitor(PlaywrightEx.Supervisor.out_of_process(PlaywrightEx))

    for {name, source} <- Engines.custom() do
      Selectors.register!(selectors, to_string(name), %{content: source})
    end

    {:ok, ref}
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, _pid, _reason}, ref), do: {:stop, {:shutdown, :driver_down}, ref}
end
