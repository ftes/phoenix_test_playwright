defmodule PhoenixTest.TestHelpers do
  @moduledoc false

  alias PhoenixTest.Playwright

  @doc """
  Converts a multi-line string into a whitespace-forgiving regex
  """
  def ignore_whitespace(string) do
    string
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(fn s -> s == "" end)
    |> Enum.map_join("\n", fn s -> "\\s*" <> s <> "\\s*" end)
    |> Regex.compile!([:dotall])
  end

  @doc """
  Replaces the current browser document with test-local body markup.

  Navigating to `about:blank` first prevents application JavaScript, styles,
  and LiveView state from leaking into the fixture.
  """
  def set_html(conn, html) do
    conn
    |> Playwright.visit("about:blank")
    |> Playwright.evaluate("html => { document.body.innerHTML = html }",
      is_function: true,
      arg: html
    )
  end
end
