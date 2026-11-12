defmodule PhoenixTest.Playwright.Supervisor do
  @moduledoc """
  Runs the local Playwright driver that connects to a remote Playwright server,
  when `ws_endpoint` is configured.

  Not needed otherwise: `PlaywrightEx.Test.BrowserPool` starts the drivers of local
  browsers on first use and stops them after the suite. Without `ws_endpoint`, this
  supervisor starts nothing.

  With `ws_endpoint`, start it in `test/test_helper.exs`:

      {:ok, _} = PhoenixTest.Playwright.Supervisor.start_link()
  """

  use Supervisor

  alias PhoenixTest.Playwright.Config

  @driver PhoenixTest.Playwright.Driver

  @doc """
  Starts the supervisor with the global `config :phoenix_test, :playwright`, and raises if that is invalid.
  """
  # Takes no config. The `[]` is what `child_spec/1` passes.
  def start_link([] \\ []) do
    # Host apps usually depend on this library with `runtime: false`, which leaves it to us.
    {:ok, _} = Application.ensure_all_started(:playwright_ex)
    # `Config.global/0` raises on an invalid config.
    Supervisor.start_link(__MODULE__, Config.global(), name: __MODULE__)
  end

  @doc false
  def driver do
    if !Process.whereis(__MODULE__) do
      raise "ws_endpoint needs `{:ok, _} = PhoenixTest.Playwright.Supervisor.start_link()` in test/test_helper.exs"
    end

    @driver
  end

  @impl true
  def init(config) do
    children =
      if config[:ws_endpoint] do
        [{PlaywrightEx.Supervisor, name: @driver}, {PhoenixTest.Playwright.DriverWatcher, @driver}]
      else
        []
      end

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
