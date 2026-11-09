defmodule PhoenixTest.StepTest do
  use PhoenixTest.Playwright.Case, async: true, trace: false

  import PhoenixTest.TestHelpers, only: [set_html: 2]

  alias PlaywrightEx.BrowserContext
  alias PlaywrightEx.Tracing

  @html """
  <input
    id="text-input"
    oninput="document.querySelector('#changed-form-data').textContent = `text: ${this.value}`"
  />
  <div id="changed-form-data"></div>
  """

  describe "step/3" do
    test "produces labels that can be seen in the trace viewer", %{conn: conn} do
      start_tracing(conn)

      conn
      |> set_html(@html)
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
      assert trace =~ ~r/Fill in form with test data.*step_test.exs.*"line":23/
      assert trace =~ ~r/Type into text input.*step_test.exs.*"line":25/
      assert trace =~ ~r/Verify form data changed.*step_test.exs.*"line":28/
    end
  end

  defp start_tracing(conn) do
    tracing = BrowserContext.tracing(conn.context)
    Tracing.start!(tracing)
  end

  defp stop_tracing(conn) do
    tracing = BrowserContext.tracing(conn.context)
    zip_file = Path.join(System.tmp_dir!(), "step-test-#{System.unique_integer([:positive])}.zip")
    Tracing.stop!(tracing, path: zip_file)

    {:ok, handle} = :zip.zip_open(String.to_charlist(zip_file), [:memory])
    {:ok, {_, trace_contents}} = :zip.zip_get(~c"trace.trace", handle)
    :ok = :zip.zip_close(handle)

    trace_contents
  end
end
