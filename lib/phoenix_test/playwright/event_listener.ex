defmodule PhoenixTest.Playwright.EventListener do
  @moduledoc """
  Background playwright event listener.

  This function starts a background process that will automatically handle events
  according to the provided callback function.

  ## Optional callback stack
  The current callback is the top most on the callback stack.
  A new callback can be set via `push_callback/2`, and the previous
  callback can be reverted to via `pop_callback/1`.
  """
  use GenServer

  defstruct [:filter, :callbacks]

  # Public API

  def push_callback(name, callback) when is_function(callback, 1) do
    GenServer.cast(name, {:push_callback, callback})
  end

  def pop_callback(name) do
    GenServer.cast(name, :pop_callback)
  end

  # Internal

  def start_link(%{guid: _, filter: _, callback: _} = args, opts \\ []) do
    GenServer.start_link(__MODULE__, args, opts)
  end

  @impl GenServer
  def init(%{guid: guid, filter: filter, callback: callback}) when is_function(callback, 1) do
    PhoenixTest.Playwright.Connection.subscribe(self(), guid)
    {:ok, %__MODULE__{filter: filter, callbacks: [callback]}}
  end

  @impl GenServer
  def handle_info({:playwright, event}, %__MODULE__{} = state) do
    callback = List.first(state.callbacks)
    if state.filter.(event) and callback, do: callback.(event)
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:push_callback, callback}, %__MODULE__{callbacks: callbacks} = state) do
    {:noreply, %{state | callbacks: [callback | callbacks]}}
  end

  def handle_cast(:pop_callback, %__MODULE__{callbacks: [_ | callbacks]} = state) do
    {:noreply, %{state | callbacks: callbacks}}
  end
end
