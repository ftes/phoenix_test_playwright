defmodule PhoenixTest.Playwright.BrowserPool do
  @moduledoc """
  Reuses browsers across test suites.
  This limits memory usage and is useful when running feature tests together with regular tests
  (high ExUnit `max_cases` concurrency such as the default: 2x number of CPU cores).

  Pools are defined up front.
  Browsers are launched lazily.
  All launched browsers are closed before the pool terminates.
  """

  use GenServer

  alias __MODULE__, as: State
  alias PhoenixTest.Playwright.Browser
  alias PhoenixTest.Playwright.Config

  defstruct [
    :size,
    :config,
    available: [],
    in_use: %{},
    waiting: []
  ]

  @type pool_id :: atom()
  @type browser :: PlaywrightEx.Browser.t()

  ## Public

  @spec checkout(pool_id()) :: browser()
  def checkout(pool) do
    timeout = Config.global(:browser_pool_checkout_timeout)
    GenServer.call(pool, :checkout, timeout)
  end

  ## Internal

  @doc false
  def start_link(opts) do
    {id, opts} = Keyword.pop!(opts, :id)
    {size, opts} = Keyword.pop(opts, :size, ceil(System.schedulers_online() / 2))

    GenServer.start_link(__MODULE__, %State{size: size, config: opts}, name: id)
  end

  @impl GenServer
  def init(state) do
    Process.flag(:trap_exit, true)
    {:ok, state}
  end

  @impl GenServer
  def handle_call(:checkout, from, state) do
    cond do
      not Enum.empty?(state.available) ->
        browser = hd(state.available)
        state = do_checkout(state, from, browser)
        {:reply, browser, state}

      map_size(state.in_use) < state.size ->
        {:ok, browser} = launch(state.config)
        state = do_checkout(state, from, browser)
        {:reply, browser, state}

      true ->
        state = Map.update!(state, :waiting, &(&1 ++ [from]))
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    case Enum.find_value(state.in_use, fn {browser, tracked} -> tracked == {pid, ref} and browser end) do
      nil -> {:noreply, state}
      browser -> {:noreply, do_checkin(state, browser)}
    end
  end

  @impl GenServer
  def terminate(_reason, state) do
    timeout = Config.global(:timeout)

    tasks =
      for browser <- state.available ++ Map.keys(state.in_use) do
        Task.async(fn -> close(browser, timeout) end)
      end

    Task.await_many(tasks, :infinity)
  end

  defp close(browser, timeout) do
    Browser.close_within(timeout, fn -> PlaywrightEx.Browser.close(browser) end)
  end

  @doc false
  defdelegate launch_browser!(config), to: Browser

  defp launch(config) do
    config = config |> Config.validate!() |> Keyword.take(Config.setup_all_keys())
    {:ok, launch_browser!(config)}
  end

  defp do_checkout(state, from, browser) do
    {from_pid, _tag} = from

    state
    |> Map.update!(:available, &(&1 -- [browser]))
    |> Map.update!(:in_use, &Map.put(&1, browser, {from_pid, Process.monitor(from_pid)}))
  end

  defp do_checkin(state, browser) do
    {{_from_pid, ref}, in_use} = Map.pop(state.in_use, browser)
    Process.demonitor(ref, [:flush])
    state = %{state | in_use: in_use, available: [browser | state.available]}

    case state.waiting do
      [from | rest] ->
        GenServer.reply(from, browser)
        %{do_checkout(state, from, browser) | waiting: rest}

      _ ->
        state
    end
  end
end
