defmodule PhoenixTest.StepTest do
  use PhoenixTest.Playwright.Case, async: true

  alias PhoenixTest.Playwright
  alias PlaywrightEx.Tracing

  describe "step/3" do
    test "produces labels that can be seen in the trace viewer", %{conn: conn} do
      {:ok, _} = Tracing.tracing_start(conn.tracing_id, timeout: timeout())
      {:ok, _} = Tracing.tracing_start_chunk(conn.tracing_id, timeout: timeout())

      conn
      |> visit("/pw/live")
      |> Playwright.step("Fill in form with test data", fn conn ->
        conn
        |> Playwright.step("Type into text input", fn conn ->
          type(conn, "#text-input", "Hello from custom step!")
        end)
        |> Playwright.step("Verify form data changed", fn conn ->
          assert_has(conn, "#changed-form-data", text: "text: Hello from custom step!")
        end)
      end)

      {:ok, zip_file} = Tracing.tracing_stop_chunk(conn.tracing_id, timeout: timeout())
      {:ok, _} = Tracing.tracing_stop(conn.tracing_id, timeout: timeout())

      {:ok, handle} = :zip.zip_open(String.to_charlist(zip_file.absolute_path), [:memory])
      {:ok, {_, trace_contents}} = :zip.zip_get(~c"trace.trace", handle)
      :ok = :zip.zip_close(handle)

      assert trace_contents =~ "Fill in form with test data"
      assert trace_contents =~ "Type into text input"
      assert trace_contents =~ "Verify form data changed"
    end
  end
end
