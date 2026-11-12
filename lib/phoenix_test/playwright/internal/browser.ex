defmodule PhoenixTest.Playwright.Browser do
  @moduledoc false

  alias PhoenixTest.Playwright.Config
  alias PhoenixTest.Playwright.Selector.Engines
  alias PlaywrightEx.BrowserType
  alias PlaywrightEx.Playwright
  alias PlaywrightEx.Test.BrowserPool

  @doc """
  A browser of `PlaywrightEx.Test.BrowserPool` (`config[:browser_pool]`), or a connection to the
  remote one if `ws_endpoint` is configured.
  Call it in `setup_all`: an exclusive browser is held by the calling scope.
  """
  def browser!(config) do
    case Config.global()[:ws_endpoint] do
      nil -> pooled!(config)
      ws_endpoint -> connect!(config, ws_endpoint)
    end
  end

  defp pooled!(config) do
    opts =
      Enum.reject(
        [
          browser_name: config[:browser],
          launch_options: config[:browser_launch_opts],
          on_start: {Engines, :register, []}
        ],
        fn {_key, value} -> is_nil(value) end
      )

    case pool_mode(config) do
      :shared -> BrowserPool.shared(opts)
      :exclusive -> BrowserPool.exclusive(opts)
    end
  end

  # A shared Firefox browser serializes input across its pages, see `PlaywrightEx.Test.BrowserPool`.
  defp pool_mode(config) do
    browser_name = config[:browser] || Application.get_env(:playwright_ex, :test, [])[:browser_name]
    config[:browser_pool] || if(browser_name == :firefox, do: :exclusive, else: :shared)
  end

  defp connect!(config, ws_endpoint) do
    browser_type = browser_type(config[:browser] || :chromium)
    opts = Keyword.take(config[:browser_launch_opts] || [], ~w(slow_mo timeout)a)

    case BrowserType.connect(browser_type, ws_endpoint, opts) do
      {:ok, browser} -> browser
      {:error, reason} -> raise "Failed to connect to Playwright browser: #{Exception.message(reason)}"
    end
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

  defp browser_type(:chromium), do: Playwright.chromium(remote_playwright())
  defp browser_type(:firefox), do: Playwright.firefox(remote_playwright())
  defp browser_type(:webkit), do: Playwright.webkit(remote_playwright())

  defp remote_playwright, do: PlaywrightEx.playwright(PhoenixTest.Playwright.Supervisor.driver())
end
