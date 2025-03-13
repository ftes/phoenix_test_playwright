defmodule PhoenixTest.Playwright.CookieArgsTest do
  use ExUnit.Case

  alias PhoenixTest.Playwright.CookieArgs
  alias PhoenixTest.Playwright.CookieTestUtils
  alias PhoenixTest.SessionOptions

  describe "from_cookie/1" do
    test "returns a map of valid args for Playwright's addCookies method" do
      cookie = CookieTestUtils.example_cookie(:plain)

      assert CookieArgs.from_cookie(cookie) == %{
               name: "plain_cookie",
               value: "the secret is mighty_boosh",
               url: "http://localhost:4002",
               secure: false,
               http_only: false,
               same_site: "Lax"
             }
    end
  end

  describe "from_session_options/1" do
    test "returns a map of valid args for Playwright's addCookies method" do
      cookie = CookieTestUtils.example_session_cookie()
      session_options = SessionOptions.session_options()

      assert CookieArgs.from_session_options(cookie, session_options) == %{
               name: "_phoenix_test_key",
               url: "http://localhost:4002",
               value: "SFMyNTY.g3QAAAABbQAAAAZzZWNyZXRtAAAADG1vbnR5X3B5dGhvbg.ba-LglcAlWpORJb__q8ViNoEXZq4kRKEwgXcmzrft1E"
             }
    end
  end
end
