defmodule PhoenixTest.Playwright.EventListener do
  @moduledoc """
  Sets up a background event listener for the session.

  This function starts a background process that will automatically handle events
  according to the provided callback function.
  """
  use GenServer

  def start_link(%{guid: _, filter: _, callback: _} = args, opts \\ []) do
    GenServer.start_link(__MODULE__, args, opts)
  end

  def init(%{guid: guid, filter: filter, callback: callback}) when is_function(callback, 1) do
    PhoenixTest.Playwright.Connection.subscribe(self(), guid)
    {:ok, %{filter: filter, callback: callback}}
  end

  def handle_info({:playwright, event}, state) do
    if state.filter.(event), do: state.callback.(event)
    {:noreply, state}
  end
end
