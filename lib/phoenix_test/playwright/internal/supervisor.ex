defmodule PhoenixTest.Playwright.Supervisor do
  @moduledoc """
  Supervises the Playwright connection and browser pools.

  Supports two transport modes:
  - **Local** (default): Spawns a local Node.js Playwright driver via Erlang Port
  - **Remote**: Connects to a remote Playwright server via WebSocket when `ws_endpoint` is configured
  """

  use Supervisor

  alias PhoenixTest.Playwright.Config

  def start_link do
    Supervisor.start_link(__MODULE__, :no_init_arg, name: __MODULE__)
  end

  @impl true
  def init(:no_init_arg) do
    config = Config.global()

    children = [
      {PlaywrightEx.Supervisor, playwright_opts(config)},
      PhoenixTest.Playwright.BrowserPoolSupervisor
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  defp playwright_opts(config) do
    base = Keyword.take(config, ~w(timeout js_logger)a)

    case config[:ws_endpoint] do
      nil -> Keyword.put(base, :executable, Config.executable())
      url -> Keyword.put(base, :ws_endpoint, ws_endpoint_with_browser(url, config))
    end
  end

  # Playwright's run-server requires the browser type as a query parameter
  defp ws_endpoint_with_browser(url, config) do
    browser = config[:browser] || :chromium
    uri = URI.parse(url)
    query = (uri.query || "") |> URI.decode_query() |> Map.put("browser", to_string(browser)) |> URI.encode_query()
    URI.to_string(%{uri | query: query})
  end
end
