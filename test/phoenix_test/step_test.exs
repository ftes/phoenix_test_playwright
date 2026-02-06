defmodule PhoenixTest.StepTest do
  use PhoenixTest.Playwright.Case, async: true

  alias PlaywrightEx.Tracing

  describe "step/3" do
    test "produces labels that can be seen in the trace viewer", %{conn: conn} do
      start_tracing(conn)

      conn
      |> visit("/pw/live")
      |> step("Fill in form with test data", fn conn ->
        conn
        |> step("Type into text input", fn conn ->
          type(conn, "#text-input", "Hello from custom step!")
        end)
        |> step("Verify form data changed", fn conn ->
          assert_has(conn, "#changed-form-data", text: "text: Hello from custom step!")
        end)
      end)

      trace = stop_tracing(conn)
      assert trace =~ ~r/Fill in form with test data.*step_test.exs.*"line":12/
      assert trace =~ ~r/Type into text input.*"line":14/
      assert trace =~ ~r/Verify form data changed.*"line":17/
    end
  end

  defp start_tracing(conn) do
    {:ok, _} = Tracing.tracing_start(conn.tracing_id, timeout: timeout())
    {:ok, _} = Tracing.tracing_start_chunk(conn.tracing_id, timeout: timeout())
  end

  defp stop_tracing(conn) do
    {:ok, zip_file} = Tracing.tracing_stop_chunk(conn.tracing_id, timeout: timeout())
    {:ok, _} = Tracing.tracing_stop(conn.tracing_id, timeout: timeout())

    {:ok, handle} = :zip.zip_open(String.to_charlist(zip_file.absolute_path), [:memory])
    {:ok, {_, trace_contents}} = :zip.zip_get(~c"trace.trace", handle)
    :ok = :zip.zip_close(handle)

    trace_contents
  end
end
