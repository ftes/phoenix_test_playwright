defmodule PhoenixTest.Playwright.Supervisor do
  @moduledoc false

  use Supervisor

  alias PhoenixTest.Playwright.Config

  def start_link do
    Supervisor.start_link(__MODULE__, :no_init_arg, name: __MODULE__)
  end

  @impl true
  def init(:no_init_arg) do
    config = Config.global()
    playwright_config = build_playwright_config(config)
    children = [{PlaywrightEx.Supervisor, playwright_config}, PhoenixTest.Playwright.BrowserPoolSupervisor]
    Supervisor.init(children, strategy: :rest_for_one)
  end

  defp build_playwright_config(config) do
    base_opts = Keyword.take(config, ~w(timeout js_logger)a)

    if ws_endpoint = config[:ws_endpoint] do
      # WebSocket mode - connect to remote Playwright server
      # Append browser type as query parameter (required by run-server)
      browser = config[:browser] || :chromium
      ws_endpoint_with_browser = append_browser_param(ws_endpoint, browser)
      Keyword.put(base_opts, :ws_endpoint, ws_endpoint_with_browser)
    else
      # Local Port mode (default) - spawn local Node.js driver
      Keyword.put(base_opts, :executable, Config.executable())
    end
  end

  defp append_browser_param(ws_endpoint, browser) do
    uri = URI.parse(ws_endpoint)
    query = URI.decode_query(uri.query || "")
    new_query = Map.put(query, "browser", to_string(browser))
    %{uri | query: URI.encode_query(new_query)} |> URI.to_string()
  end
end
