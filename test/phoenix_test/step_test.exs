defmodule PhoenixTest.StepTest.TraceCase do
  @moduledoc false
  # A template's own `setup` runs before those its `using` brings in, so this `on_exit` runs
  # after the one of `use PlaywrightEx.Test`, which writes `trace.zip`.
  use ExUnit.CaseTemplate

  import ExUnit.Assertions

  using do
    quote do
      use PlaywrightEx.Test
    end
  end

  setup %{test_pid: test_pid} do
    on_exit(fn ->
      trace_zip = Path.join(PlaywrightEx.Test.info(test_pid).output_dir, "trace.zip")
      {:ok, handle} = :zip.zip_open(String.to_charlist(trace_zip), [:memory])
      {:ok, {_, trace}} = :zip.zip_get(~c"test.trace", handle)
      :ok = :zip.zip_close(handle)

      steps = for line <- String.split(trace, "\n"), line =~ ~s("method":"test.step"), do: JSON.decode!(line)
      [outer, inner1, inner2] = steps
      assert outer["title"] == "Fill in form with test data"
      assert [inner1["title"], inner2["title"]] == ["Type into text input", "Verify form data changed"]
      assert inner1["parentId"] == outer["callId"] and inner2["parentId"] == outer["callId"]
      assert Enum.all?(steps, &String.ends_with?(hd(&1["stack"])["file"], "test/phoenix_test/step_test.exs"))
    end)
  end
end

defmodule PhoenixTest.StepTest do
  use PhoenixTest.StepTest.TraceCase, async: true

  import PhoenixTest
  import PhoenixTest.Playwright, only: [step: 3, type: 3]
  import PhoenixTest.TestHelpers, only: [set_html: 2]

  alias PhoenixTest.Playwright.Case, as: PlaywrightCase

  setup_all :do_setup_all
  setup :do_setup

  @moduletag trace: :on

  @html """
  <input
    id="text-input"
    oninput="document.querySelector('#changed-form-data').textContent = `text: ${this.value}`"
  />
  <div id="changed-form-data"></div>
  """

  describe "step/3" do
    test "produces nested labels at their call site in the trace", %{conn: conn} do
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
    end
  end

  defp do_setup_all(context), do: PlaywrightCase.do_setup_all(context)
  defp do_setup(context), do: PlaywrightCase.do_setup(context)
end
