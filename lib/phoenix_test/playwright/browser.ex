defmodule PhoenixTest.Playwright.Browser do
  @moduledoc """
  Interact with a Playwright `Browser`.

  There is no official documentation, since this is considered Playwright internal.

  References:
  - https://github.com/microsoft/playwright/blob/main/packages/playwright-core/src/client/browser.ts
  """

  import PhoenixTest.Playwright.Connection, only: [post: 1]

  @doc """
  Start a new browser context and return its `guid`.
  """
  def new_context(browser_id, opts \\ []) do
    params = Map.new(opts)
    resp = post(guid: browser_id, method: :new_context, params: params)
    resp.result.context.guid
  end
end
