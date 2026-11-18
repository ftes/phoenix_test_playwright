defmodule PhoenixTest.Playwright.CaseRecordingTest.TraceCase do
  @moduledoc false
  # A template's own `setup` runs before those its `using` brings in, so this `on_exit` runs
  # after the one of `use Playwright.Test`, which writes `trace.zip`.
  use ExUnit.CaseTemplate

  import ExUnit.Assertions

  using do
    quote do
      use PhoenixTest.Playwright.Case, async: true, trace: :on
    end
  end

  setup %{test_pid: test_pid} do
    on_exit(fn ->
      assert File.exists?(Path.join(Playwright.Test.info(test_pid).output_dir, "trace.zip"))
    end)
  end
end

defmodule PhoenixTest.Playwright.CaseRecordingTest do
  use PhoenixTest.Playwright.CaseRecordingTest.TraceCase

  import PhoenixTest.TestHelpers, only: [set_html: 2]

  test "use Case, trace: :on records a trace", %{conn: conn} do
    conn
    |> set_html("<h1>Traced</h1>")
    |> assert_has("h1")
  end
end
