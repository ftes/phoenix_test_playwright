defmodule PhoenixTest.Playwright.CookieTestUtils do
  @moduledoc false

  alias PhoenixTest.Playwright.CookieArgs
  alias PhoenixTest.Plugs.RequireCookiePlug

  @spec example_cookie(atom()) :: CookieArgs.cookie()
  def example_cookie(flavor) do
    flavor
    |> RequireCookiePlug.cookie_options()
    |> Keyword.merge(
      url: Application.fetch_env!(:phoenix_test, :base_url),
      name: RequireCookiePlug.cookie_name(flavor),
      value: RequireCookiePlug.valid_cookie_value(flavor)
    )
  end

  @spec example_session_cookie() :: CookieArgs.cookie()
  def example_session_cookie do
    [
      url: Application.fetch_env!(:phoenix_test, :base_url),
      value: %{secret: "monty_python"}
    ]
  end
end
