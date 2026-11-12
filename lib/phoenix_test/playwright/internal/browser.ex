defmodule PhoenixTest.Playwright.Browser do
  @moduledoc false

  alias PhoenixTest.Playwright.Config
  alias PhoenixTest.Playwright.Selector.Engines
  alias PlaywrightEx.Test.BrowserPool

  @doc """
  A browser of `PlaywrightEx.Test.BrowserPool` (`config[:browser_pool]`), launched locally or,
  with `config :playwright_ex, :test, connect_options: ...`, connected to a remote server.
  Call it in `setup_all`: an exclusive browser is held by the calling scope.
  """
  def browser!(config) do
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
end
