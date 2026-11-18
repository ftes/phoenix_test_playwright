defmodule PhoenixTest.Playwright.CookieArgsTest do
  use ExUnit.Case

  alias PhoenixTest.Playwright.CookieArgs

  describe("from_cookie/1") do
    test "adds default url" do
      cookie = [name: "name", value: "42"]

      assert CookieArgs.from_cookie(cookie) == %{
               name: "name",
               value: "42",
               url: Application.get_env(:phoenix_test, :base_url)
             }
    end

    test "allows overriding values" do
      cookie = [
        name: "name",
        value: "42",
        url: "#{Application.get_env(:phoenix_test, :base_url)}/path",
        same_site: "Lax",
        http_only: true,
        secure: true
      ]

      assert CookieArgs.from_cookie(cookie) == %{
               name: "name",
               value: "42",
               url: "#{Application.get_env(:phoenix_test, :base_url)}/path",
               secure: true,
               httpOnly: true,
               sameSite: "Lax"
             }
    end
  end

  describe "from_session_options/1" do
    test "returns a map of valid args for Playwright's addCookies method" do
      cookie = [value: %{secret: "monty_python"}]
      session_options = PhoenixTest.WebApp.Endpoint.session_options()

      assert CookieArgs.from_session_options(cookie, session_options) == %{
               name: "_phoenix_key",
               url: Application.get_env(:phoenix_test, :base_url),
               value: "SFMyNTY.g3QAAAABbQAAAAZzZWNyZXRtAAAADG1vbnR5X3B5dGhvbg.fgc5Hcsik_B4PSRMNkRdPd3Jo147_w5_msEz39ILXJw"
             }
    end
  end

  describe "default url" do
    test "is the origin of the session's base_url" do
      assert %{url: "http://other.test:4000"} =
               CookieArgs.from_cookie([name: "a", value: "b"], "http://other.test:4000/page/")
    end

    test "is the base_url's host as domain for a cookie with a path" do
      cookie = CookieArgs.from_cookie([name: "a", value: "b", path: "/admin"], "http://other.test:4000/page/")
      assert %{domain: "other.test", path: "/admin"} = cookie
      refute Map.has_key?(cookie, :url)
    end

    test "is the https base_url's host as a secure domain for a cookie with a path" do
      assert %{domain: "other.test", secure: true} =
               CookieArgs.from_cookie([name: "a", value: "b", path: "/admin"], "https://other.test")
    end

    test "is not added to a cookie with a domain, whose path defaults to /" do
      cookie = CookieArgs.from_cookie([name: "a", value: "b", domain: "localhost"], "http://other.test")
      assert %{domain: "localhost", path: "/"} = cookie
      refute Map.has_key?(cookie, :url)
    end
  end
end
