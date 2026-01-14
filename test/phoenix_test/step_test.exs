defmodule PhoenixTest.StepTest do
  use PhoenixTest.Playwright.Case, async: true

  alias PhoenixTest.Playwright

  describe "step/3" do
    test "returns the conn unchanged", %{conn: conn_before} do
      conn_after =
        conn_before
        |> visit("/pw/live")
        |> Playwright.step("Test step", fn c -> c end)

      assert conn_after == conn_before
    end

    @tag :demo
    @tag trace: :open
    # The visibility of the labels must be confirmed manually in the trace viewer
    test "produces labels that can be seen in the trace viewer", %{conn: conn} do
      conn
      |> visit("/pw/live")
      |> assert_has("h1", text: "Playwright")
      |> Playwright.step("Fill in form with test data", fn conn ->
        conn
        |> Playwright.step("Type into text input", fn conn ->
          type(conn, "#text-input", "Hello from custom step!")
        end)
        |> Playwright.step("Verify form data changed", fn conn ->
          assert_has(conn, "#changed-form-data", text: "text: Hello from custom step!")
        end)
      end)
      |> click_link(nil, "Navigate", exact: true)
      |> assert_has("h1", text: "Other")
    end
  end
end
