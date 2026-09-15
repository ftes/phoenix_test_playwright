defmodule PhoenixTest.Playwright.EventRecorder do
  @moduledoc false
  use GenServer

  defstruct [:filter, events: [], waiter: nil, timer: nil]

  def pop(name, timeout) do
    GenServer.call(name, {:pop, timeout}, :infinity)
  end

  def start_link(%{guid: _, filter: _} = args, opts \\ []) do
    GenServer.start_link(__MODULE__, args, opts)
  end

  @impl GenServer
  def init(%{guid: guid, filter: filter}) when is_function(filter, 1) do
    PlaywrightEx.subscribe(guid, pid: self())
    {:ok, %__MODULE__{filter: filter}}
  end

  @impl GenServer
  def handle_call({:pop, _timeout}, _from, %{events: [event | events]} = state) do
    {:reply, {:ok, event}, %{state | events: events}}
  end

  def handle_call({:pop, 0}, _from, %{events: [], waiter: nil} = state) do
    {:reply, {:error, :timeout}, state}
  end

  def handle_call({:pop, timeout}, from, %{events: [], waiter: nil} = state) do
    timer = if timeout != :infinity, do: :erlang.start_timer(timeout, self(), :pop)
    {:noreply, %{state | waiter: from, timer: timer}}
  end

  def handle_call({:pop, _timeout}, _from, _state) do
    raise "EventRecorder already has a pending pop"
  end

  @impl GenServer
  def handle_info({:playwright_msg, event}, %__MODULE__{} = state) do
    if state.filter.(event) do
      {:noreply, record_event(event, state)}
    else
      {:noreply, state}
    end
  end

  def handle_info({:timeout, timer, :pop}, %{timer: timer, waiter: waiter} = state) do
    GenServer.reply(waiter, {:error, :timeout})
    {:noreply, %{state | waiter: nil, timer: nil}}
  end

  def handle_info({:timeout, _stale_timer, :pop}, state), do: {:noreply, state}

  defp record_event(event, %__MODULE__{waiter: nil, events: events} = state) do
    %{state | events: events ++ [event]}
  end

  defp record_event(event, %__MODULE__{waiter: waiter} = state) do
    if state.timer, do: Process.cancel_timer(state.timer)
    GenServer.reply(waiter, {:ok, event})
    %{state | waiter: nil, timer: nil}
  end
end
