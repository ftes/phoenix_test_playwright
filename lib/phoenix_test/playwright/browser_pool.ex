defmodule PhoenixTest.Playwright.BrowserPool do
  @moduledoc """
  A pool of browser instances that can be shared across tests.

  The pool manages up to 4 browser instances per unique browser configuration.
  Browsers are launched lazily (on first checkout) and reused across tests.
  Each unique browser configuration gets its own pool process.

  ## Pool Configuration

  The pool identity is based on these configuration keys:
  - `:browser` - Browser type (`:chromium`, `:firefox`, `:webkit`)
  - `:headless` - Run in headless mode
  - `:slow_mo` - Slow down operations
  - `:executable_path` - Path to browser executable
  - `:browser_launch_timeout` - Timeout for launching browser

  Tests with different configurations will use different pools.
  """

  use GenServer

  alias PhoenixTest.Playwright.Connection

  require Logger

  @pool_config_keys [:browser, :headless, :slow_mo, :executable_path, :browser_launch_timeout]

  defmodule State do
    @moduledoc false
    defstruct [
      :config,
      available: [],
      in_use: %{},
      waiting: :queue.new(),
      max_size: 4
    ]
  end

  ## Public API

  @doc """
  Checkout a browser from the pool.

  If a browser is available, returns immediately.
  If all browsers are in use but the pool hasn't reached max size, launches a new browser.
  If the pool is at max capacity, waits until a browser becomes available.

  Returns `{:ok, browser_id}`.
  """
  def checkout(config) do
    pool_pid = ensure_pool_started(config)
    GenServer.call(pool_pid, :checkout, :infinity)
  end

  @doc """
  Return a browser to the pool.

  The browser becomes available for other tests to use.
  """
  def checkin(browser_id) do
    # Find the pool that owns this browser by trying all registered pools
    case find_pool_for_browser(browser_id) do
      {:ok, pool_pid} ->
        GenServer.call(pool_pid, {:checkin, browser_id})

      :error ->
        Logger.warning("Attempted to checkin unknown browser #{browser_id}")
        :ok
    end
  end

  ## GenServer Callbacks

  @doc false
  def start_link(config) do
    name = via_tuple(config)
    GenServer.start_link(__MODULE__, config, name: name)
  end

  @impl GenServer
  def init(config) do
    # Trap exits so we can clean up browsers on shutdown
    Process.flag(:trap_exit, true)

    {:ok, %State{config: config}}
  end

  @impl GenServer
  def handle_call(:checkout, from, state) do
    {from_pid, _tag} = from

    case state.available do
      # Case 1: Browser available, return immediately
      [browser_id | rest] ->
        ref = Process.monitor(from_pid)
        state = %{state | available: rest, in_use: Map.put(state.in_use, browser_id, {from_pid, ref})}
        {:reply, {:ok, browser_id}, state}

      # Case 2: No available browsers
      [] ->
        if map_size(state.in_use) < state.max_size do
          # Can launch new browser (under max size)
          case launch_browser(state.config) do
            {:ok, browser_id} ->
              ref = Process.monitor(from_pid)
              state = %{state | in_use: Map.put(state.in_use, browser_id, {from_pid, ref})}
              {:reply, {:ok, browser_id}, state}

            {:error, reason} ->
              {:reply, {:error, reason}, state}
          end
        else
          # All browsers in use, queue the request
          state = %{state | waiting: :queue.in(from, state.waiting)}
          {:noreply, state}
        end
    end
  end

  @impl GenServer
  def handle_call({:checkin, browser_id}, _from, state) do
    # Remove from in_use and demonitor
    case Map.pop(state.in_use, browser_id) do
      {nil, _} ->
        # Browser not tracked, ignore
        {:reply, :ok, state}

      {{_pid, ref}, new_in_use} ->
        Process.demonitor(ref, [:flush])

        # Check if anyone is waiting
        case :queue.out(state.waiting) do
          {{:value, waiting_from}, new_waiting} ->
            # Give the browser to the waiting caller
            {waiting_pid, _tag} = waiting_from
            new_ref = Process.monitor(waiting_pid)

            state = %{
              state
              | in_use: Map.put(new_in_use, browser_id, {waiting_pid, new_ref}),
                waiting: new_waiting
            }

            GenServer.reply(waiting_from, {:ok, browser_id})
            {:reply, :ok, state}

          {:empty, _} ->
            # No one waiting, add back to available
            state = %{state | available: [browser_id | state.available], in_use: new_in_use}
            {:reply, :ok, state}
        end
    end
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    # A process that checked out a browser has died
    # Find and auto-checkin the browser
    case Enum.find(state.in_use, fn {_browser_id, {owner_pid, owner_ref}} ->
           owner_pid == pid && owner_ref == ref
         end) do
      {browser_id, _} ->
        Logger.debug("Auto-checking in browser #{browser_id} after owner process died")
        # Call our own checkin handler, but extract the state from the reply
        {:reply, :ok, new_state} = handle_call({:checkin, browser_id}, self(), state)
        {:noreply, new_state}

      nil ->
        {:noreply, state}
    end
  end

  @impl GenServer
  def terminate(_reason, state) do
    # Close all browsers (both available and in_use)
    all_browsers = state.available ++ Map.keys(state.in_use)

    for browser_id <- all_browsers do
      Logger.debug("Closing browser #{browser_id} on pool shutdown")
      Connection.post(guid: browser_id, method: :close)
    end

    :ok
  end

  ## Private Helpers

  defp ensure_pool_started(config) do
    pool_config = Keyword.take(config, @pool_config_keys)
    name = via_tuple(pool_config)

    case GenServer.whereis(name) do
      nil ->
        # Start the pool under the dynamic supervisor
        case DynamicSupervisor.start_child(
               PhoenixTest.Playwright.BrowserPool.Supervisor,
               {__MODULE__, pool_config}
             ) do
          {:ok, pid} -> pid
          {:error, {:already_started, pid}} -> pid
        end

      pid ->
        pid
    end
  end

  defp via_tuple(config) do
    pool_config = Keyword.take(config, @pool_config_keys)
    config_hash = :erlang.phash2(pool_config)
    {:via, Registry, {PhoenixTest.Playwright.BrowserPool.Registry, config_hash}}
  end

  defp launch_browser(config) do
    Connection.ensure_started()
    {browser, opts} = Keyword.pop!(config, :browser)
    browser_id = Connection.launch_browser(browser, opts)
    {:ok, browser_id}
  rescue
    e ->
      Logger.error("Failed to launch browser: #{Exception.message(e)}")
      {:error, e}
  end

  defp find_pool_for_browser(browser_id) do
    # Check all registered pools to find which one owns this browser
    PhoenixTest.Playwright.BrowserPool.Registry
    |> Registry.select([{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2"}}]}])
    |> Enum.find_value(:error, fn {_config_hash, pool_pid} ->
      if Process.alive?(pool_pid) do
        try do
          state = :sys.get_state(pool_pid, 1000)

          if browser_id in state.available || Map.has_key?(state.in_use, browser_id) do
            {:ok, pool_pid}
          end
        catch
          :exit, _ -> nil
        end
      else
        nil
      end
    end)
  end
end
