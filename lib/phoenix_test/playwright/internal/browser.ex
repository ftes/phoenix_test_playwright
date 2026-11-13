defmodule PhoenixTest.Playwright.Browser do
  @moduledoc false

  alias PhoenixTest.Playwright.Selector.Engines
  alias PlaywrightEx.Test.BrowserPool

  @doc """
  A browser of `PlaywrightEx.Test.BrowserPool`, launched locally or, with
  `config :playwright_ex, :test, connect_options: ...`, connected to a remote server.
  Call it in `setup_all`: the test module holds it until it ends.
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

    BrowserPool.browser(opts)
  end
end
