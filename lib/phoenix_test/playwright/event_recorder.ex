defmodule PhoenixTest.Playwright.EventRecorder do
  @moduledoc """
  Background playwright event recorder.

  Recorded events can be retrieved in LIFO order (last in first out).
  """
  use GenServer

  # Public API

  def events(name) do
    GenServer.call(name, :events)
  end

  # Internal

  def start_link(%{guid: _, filter: _} = args, opts \\ []) do
    GenServer.start_link(__MODULE__, args, opts)
  end

  @impl GenServer
  def init(%{guid: guid, filter: filter}) do
    PhoenixTest.Playwright.Connection.subscribe(self(), guid)
    {:ok, %{filter: filter, events: []}}
  end

  @impl GenServer
  def handle_info({:playwright, event}, state) do
    if state.filter.(event) do
      {:noreply, Map.update!(state, :events, &[event | &1])}
    else
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_call(:events, _from, state) do
    {:reply, state.events, state}
  end
end
