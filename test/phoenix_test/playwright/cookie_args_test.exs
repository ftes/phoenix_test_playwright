defmodule PhoenixTest.Playwright.CookieArgsTest do
  use ExUnit.Case

  alias PhoenixTest.Playwright.CookieArgs

  describe("from_cookie/1") do
    test "adds default url" do
      cookie = [name: "name", value: "42"]

      assert CookieArgs.from_cookie(cookie) == %{name: "name", value: "42", url: "http://localhost:4002"}
    end

    test "allows overriding values" do
      cookie = [
        name: "name",
        value: "42",
        url: "http://localhost:4002/path",
        same_site: "Lax",
        http_only: true,
        secure: true
      ]

      assert CookieArgs.from_cookie(cookie) == %{
               name: "name",
               value: "42",
               url: "http://localhost:4002/path",
               secure: true,
               http_only: true,
               same_site: "Lax"
             }
    end
  end

  describe "from_session_options/1" do
    test "returns a map of valid args for Playwright's addCookies method" do
      cookie = [value: %{secret: "monty_python"}]
      session_options = PhoenixTest.Endpoint.session_options()

      assert CookieArgs.from_session_options(cookie, session_options) == %{
               name: "_phoenix_test_key",
               url: "http://localhost:4002",
               value: "SFMyNTY.g3QAAAABbQAAAAZzZWNyZXRtAAAADG1vbnR5X3B5dGhvbg.ba-LglcAlWpORJb__q8ViNoEXZq4kRKEwgXcmzrft1E"
             }
    end
  end
end
