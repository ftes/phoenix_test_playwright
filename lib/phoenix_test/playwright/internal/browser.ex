defmodule PhoenixTest.Playwright.Browser do
  @moduledoc false

  alias PhoenixTest.Playwright.Config
  alias PlaywrightEx.BrowserType
  alias PlaywrightEx.Playwright
  alias PlaywrightEx.TimeoutError

  @doc """
  Launches a Playwright browser, or connects to the remote one if `ws_endpoint` is configured,
  with helpful error messages on failure.
  """
  def launch_browser!(config) do
    {launch_timeout, opts} = Keyword.pop!(config, :browser_launch_timeout)
    {browser, opts} = Keyword.pop!(opts, :browser)
    {launch_opts, opts} = Keyword.pop!(opts, :browser_launch_opts)
    opts = opts |> Keyword.put(:timeout, Config.driver_timeout(launch_timeout)) |> Keyword.delete(:browser_pool)
    opts = Keyword.merge(opts, launch_opts)

    case launch_or_connect(browser_type(browser), Config.global()[:ws_endpoint], opts) do
      {:ok, browser} ->
        browser

      {:error, %TimeoutError{stack: stack, message: message}} ->
        raise """
        Timed out while launching the Playwright browser, #{browser |> to_string() |> String.capitalize()}. #{message}

        You may need to increase the :browser_launch_timeout option in config/test.exs:

            config :phoenix_test,
              playwright: [
                browser_launch_timeout: 10_000,
                # other Playwright options...
              ],
              # other phoenix_test options...

        Playwright backtrace:

        #{stack}
        """

      {:error, reason} ->
        raise "Failed to launch Playwright browser: #{inspect(reason)}"
    end
  end

  @doc """
  Runs a Playwright `close` call, which takes no timeout, for at most `timeout`.
  """
  def close_within(timeout, fun) do
    within(timeout, fun)
    :ok
  end

  @doc """
  Runs a Playwright call that takes no timeout, for at most `Config.client_timeout(timeout)`.
  """
  def within(timeout, fun) do
    task = Task.async(fun)

    case Task.yield(task, Config.client_timeout(timeout)) || Task.shutdown(task) do
      {:ok, result} -> {:ok, result}
      _timed_out_or_exited -> :timeout
    end
  end

  defp launch_or_connect(browser_type, nil, opts), do: BrowserType.launch(browser_type, opts)

  defp launch_or_connect(browser_type, ws_endpoint, opts) do
    BrowserType.connect(browser_type, ws_endpoint, Keyword.take(opts, ~w(slow_mo timeout)a))
  end

  defp browser_type(:chromium), do: Playwright.chromium(PlaywrightEx.playwright())
  defp browser_type(:firefox), do: Playwright.firefox(PlaywrightEx.playwright())
  defp browser_type(:webkit), do: Playwright.webkit(PlaywrightEx.playwright())
end
