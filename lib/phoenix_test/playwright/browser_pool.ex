defmodule PhoenixTest.Playwright.BrowserPool do
  @moduledoc """
  Experimental browser pooling. Reuses browsers across test suites.
  This limits memory usage and is useful when running feature tests together with regular tests
  (high ExUnit `max_cases` concurrency such as the default: 2x number of CPU cores).

  Pools are defined up front.
  Browsers are launched lazily.

  Usage:

  ```ex
  # test/test_helper.exs
  {:ok, _} =
    Supervisor.start_link(
      [
        {PhoenixTest.Playwright.BrowserPool, name: :normal_chromium, size: System.schedulers_online(), browser: :chromium},
        {PhoenixTest.Playwright.BrowserPool, name: :slow_chromium, size: 4, browser: :chromium, slow_mo: 100},
      ],
      strategy: :one_for_one
    )

  # configure pool per test module
  # test/my_test.exs
  defmodule PhoenixTest.PlaywrightBrowserPoolTest do
    use PhoenixTest.Playwright.Case,
      async: true,
      browser_pool: :normal_chromium
  end

  # or configure globally
  # test/test.exs
  config :phoenix_test,
    playwright: [
      browser_pool: :normal_chromium,
      browser_pool_checkout_timeout: to_timeout(minute: 10)
    ]
  ```
  """

  use GenServer

  alias __MODULE__, as: State
  alias PhoenixTest.Playwright

  defstruct [
    :size,
    :config,
    available: [],
    in_use: %{},
    waiting: []
  ]

  @type pool :: GenServer.server()
  @type browser_id :: binary()

  ## Public

  @spec checkout(pool()) :: browser_id()
  def checkout(pool) do
    timeout = Playwright.Config.global(:browser_pool_checkout_timeout)
    GenServer.call(pool, :checkout, timeout)
  end

  ## Internal

  @doc false
  def start_link(opts) do
    {name, opts} = Keyword.pop!(opts, :name)
    {size, opts} = Keyword.pop!(opts, :size)

    GenServer.start_link(__MODULE__, %State{size: size, config: opts}, name: name)
  end

  @impl GenServer
  def init(state) do
    # Trap exits so we can clean up browsers on shutdown
    Process.flag(:trap_exit, true)
    {:ok, state}
  end

  @impl GenServer
  def handle_call(:checkout, from, state) do
    cond do
      length(state.available) > 0 ->
        browser_id = hd(state.available)
        state = do_checkout(state, from, browser_id)
        {:reply, browser_id, state}

      map_size(state.in_use) < state.size ->
        browser_id = launch(state.config)
        state = do_checkout(state, from, browser_id)
        {:reply, browser_id, state}

      true ->
        state = Map.update!(state, :waiting, &(&1 ++ [from]))
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    case Enum.find_value(state.in_use, fn {browser_id, tracked} -> tracked == {pid, ref} and browser_id end) do
      nil -> {:noreply, state}
      browser_id -> {:noreply, do_checkin(state, browser_id)}
    end
  end

  defp launch(config) do
    config = config |> Playwright.Config.validate!() |> Keyword.take(Playwright.Config.setup_all_keys())

    {type, config} = Keyword.pop!(config, :browser)
    Playwright.Connection.ensure_started()
    Playwright.Connection.launch_browser(type, config)
  end

  defp do_checkout(state, from, browser_id) do
    {from_pid, _tag} = from

    state
    |> Map.update!(:available, &(&1 -- [browser_id]))
    |> Map.update!(:in_use, &Map.put(&1, browser_id, {from_pid, Process.monitor(from_pid)}))
  end

  defp do_checkin(state, browser_id) do
    {{_from_pid, ref}, in_use} = Map.pop(state.in_use, browser_id)
    Process.demonitor(ref, [:flush])
    state = %{state | in_use: in_use, available: [browser_id | state.available]}

    case state.waiting do
      [from | rest] ->
        GenServer.reply(from, browser_id)
        %{do_checkout(state, from, browser_id) | waiting: rest}

      _ ->
        state
    end
  end
end
