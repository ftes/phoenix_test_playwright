defmodule PhoenixTest.Playwright.EctoSandboxAsyncFalseTest do
  use PhoenixTest.Playwright.Case, async: false

  import PhoenixTest.TestHelpers, only: [set_html: 2]

  describe "new_session/2" do
    test "can create a second session in the same async: false test", context do
      context.conn
      |> set_html("<h1>First session</h1>")
      |> assert_has("h1", text: "First session")

      config = PhoenixTest.Playwright.Config.validate!(%{})
      conn2 = PhoenixTest.Playwright.Case.new_session(config, context)

      conn2
      |> set_html("<h1>Second session</h1>")
      |> assert_has("h1", text: "Second session")
    end
  end

  for delay_ms <- [0, 100] do
    @delay_ms delay_ms

    describe "delay: #{delay_ms}ms requires ecto_sandbox_stop_owner_delay to prevent 'is still using a connection from owner' errors" do
      @describetag ecto_sandbox_stop_owner_delay: delay_ms + 100
      @describetag :capture_log

      setup %{conn: conn} do
        [conn: visit(conn, "/pw/live/ecto?delay_ms=#{@delay_ms}")]
      end

      test "shows version", %{conn: conn} do
        assert_has(conn, "div", text: "Version: PostgreSQL")
      end

      test "shows long running query result", %{conn: conn} do
        assert_has(conn, "div", text: "Long running: void")
      end

      test "shows delayed version", %{conn: conn} do
        assert_has(conn, "div", text: "Delayed version: PostgreSQL")
      end
    end
  end
end
