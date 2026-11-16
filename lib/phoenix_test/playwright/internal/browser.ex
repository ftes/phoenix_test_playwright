defmodule PhoenixTest.Playwright.Browser do
  @moduledoc false

  alias PhoenixTest.Playwright.Selector.Engines
  alias Playwright.Test.BrowserPool

  @doc """
  A browser of `Playwright.Test.BrowserPool`, launched locally or, with
  `config :playwright, :test, connect_options: ...`, connected to a remote server.
  Call it in `setup_all`: the test module holds it until it ends.
  """
  def browser!(config) do
    # A dependency of `runtime: false` (as the README installs this library) doesn't start its own.
    {:ok, _apps} = Application.ensure_all_started(:playwright)

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
