defmodule PhoenixTest.Playwright.Browser do
  @moduledoc false

  alias PhoenixTest.Playwright.Selector.Engines
  alias Playwright.Test.BrowserPool

  @doc """
  A browser of `Playwright.Test.BrowserPool`, of the module's `browser_name` and `launch_options`,
  launched locally or, with `connect_options`, connected to a remote server.
  Call it in `setup_all`: the test module holds it until it ends.
  """
  def browser! do
    # A dependency of `runtime: false` (as the README installs this library) doesn't start its own.
    {:ok, _apps} = Application.ensure_all_started(:playwright)
    BrowserPool.browser(on_start: {Engines, :register, []})
  end
end
