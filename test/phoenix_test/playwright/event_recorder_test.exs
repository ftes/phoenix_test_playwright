defmodule PhoenixTest.Playwright.EventRecorderTest do
  use ExUnit.Case, async: true

  alias PhoenixTest.Playwright.EventRecorder

  setup do
    recorder =
      start_supervised!(
        {EventRecorder, %{guid: "recorder-#{System.unique_integer([:positive])}", filter: fn _ -> true end}}
      )

    %{recorder: recorder}
  end

  test "infinite waits receive a later event without starting a timer", %{recorder: recorder} do
    task = Task.async(fn -> EventRecorder.pop(recorder, :infinity) end)
    assert await_waiter(recorder).timer == nil
    assert Task.yield(task, 20) == nil
    send(recorder, {:playwright_msg, :download})
    assert Task.await(task) == {:ok, :download}
  end

  test "zero returns a queued event or times out immediately", %{recorder: recorder} do
    assert EventRecorder.pop(recorder, 0) == {:error, :timeout}
    send(recorder, {:playwright_msg, :download})
    assert EventRecorder.pop(recorder, 0) == {:ok, :download}
    assert :sys.get_state(recorder).waiter == nil
  end

  test "a finite timeout leaves the recorder ready for another wait", %{recorder: recorder} do
    assert EventRecorder.pop(recorder, 10) == {:error, :timeout}
    task = Task.async(fn -> EventRecorder.pop(recorder, :infinity) end)
    await_waiter(recorder)
    send(recorder, {:playwright_msg, :download})
    assert Task.await(task) == {:ok, :download}
  end

  test "an earlier timer cannot interrupt a later infinite wait", %{recorder: recorder} do
    first = Task.async(fn -> EventRecorder.pop(recorder, 10_000) end)
    timer = await_waiter(recorder).timer
    send(recorder, {:playwright_msg, :first})
    assert Task.await(first) == {:ok, :first}
    assert Process.read_timer(timer) == false

    second = Task.async(fn -> EventRecorder.pop(recorder, :infinity) end)
    await_waiter(recorder)
    # Cancellation cannot remove a timeout that was already sent.
    send(recorder, {:timeout, timer, :pop})
    assert Task.yield(second, 20) == nil
    send(recorder, {:playwright_msg, :second})
    assert Task.await(second) == {:ok, :second}
  end

  defp await_waiter(recorder, attempts \\ 100)
  defp await_waiter(_recorder, 0), do: flunk("recorder did not start waiting")

  defp await_waiter(recorder, attempts) do
    case :sys.get_state(recorder) do
      %{waiter: nil} ->
        Process.sleep(5)
        await_waiter(recorder, attempts - 1)

      state ->
        state
    end
  end
end
