defmodule PhoenixTest.Playwright.Browser do
  @moduledoc false

  alias PhoenixTest.Playwright.Config
  alias PhoenixTest.Playwright.Selector.Engines
  alias PlaywrightEx.BrowserType
  alias PlaywrightEx.Playwright
  alias PlaywrightEx.Test.BrowserPool
  alias PlaywrightEx.TimeoutError

  @doc """
  A browser of `PlaywrightEx.Test.BrowserPool` (`config[:browser_pool]`), or a connection to the
  remote one if `ws_endpoint` is configured, with helpful error messages on failure.
  Call it in `setup_all`: an exclusive browser is held by the calling scope.
  """
  def browser!(config) do
    case Config.global()[:ws_endpoint] do
      nil -> pooled!(config)
      ws_endpoint -> connect!(config, ws_endpoint)
    end
  end

  @doc "`PlaywrightEx.Test.BrowserPool` options of a validated config."
  def pool_opts(config) do
    shorthands =
      for {key, launch_key} <- [executable_path: :executable_path, headless: :headless, slow_mo: :slow_mo],
          value = config[key],
          !is_nil(value),
          do: {launch_key, value}

    timeout = if timeout = config[:browser_launch_timeout], do: [timeout: Config.driver_timeout(timeout)], else: []
    launch_options = shorthands |> Keyword.merge(timeout) |> Keyword.merge(config[:browser_launch_opts] || [])

    Enum.reject(
      [browser_name: config[:browser], launch_options: launch_options, on_start: {Engines, :register, []}],
      fn {_key, value} -> is_nil(value) end
    )
  end

  defp pooled!(config) do
    opts = pool_opts(config)

    try do
      case pool_mode(config, opts) do
        :shared -> BrowserPool.shared(opts)
        :exclusive -> BrowserPool.exclusive(opts)
      end
    rescue
      error in TimeoutError -> raise_launch_timeout(error, opts[:browser_name])
    end
  end

  # A shared Firefox browser serializes input across its pages, see `PlaywrightEx.Test.BrowserPool`.
  defp pool_mode(config, opts) do
    browser_name = opts[:browser_name] || Application.get_env(:playwright_ex, :test, [])[:browser_name]
    config[:browser_pool] || if(browser_name == :firefox, do: :exclusive, else: :shared)
  end

  defp connect!(config, ws_endpoint) do
    browser_type = browser_type(config[:browser] || :chromium)
    opts = config |> pool_opts() |> Keyword.fetch!(:launch_options) |> Keyword.take(~w(slow_mo timeout)a)

    case BrowserType.connect(browser_type, ws_endpoint, opts) do
      {:ok, browser} -> browser
      {:error, %TimeoutError{} = error} -> raise_launch_timeout(error, config[:browser])
      {:error, reason} -> raise "Failed to connect to Playwright browser: #{inspect(reason)}"
    end
  end

  defp raise_launch_timeout(%TimeoutError{stack: stack, message: message}, browser_name) do
    raise """
    Timed out while launching the Playwright browser, #{(browser_name || :chromium) |> to_string() |> String.capitalize()}. #{message}

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
