defmodule PhoenixTest.Playwright.BrowserContext do
  @moduledoc """
  Interact with a Playwright `BrowserContext`.

  There is no official documentation, since this is considered Playwright internal.

  References:
  - https://github.com/microsoft/playwright/blob/main/packages/playwright-core/src/client/browserContext.ts
  """

  import PhoenixTest.Playwright.Connection, only: [post: 1, initializer: 1]

  alias PhoenixTest.Playwright.CookieArgs

  @doc """
  Open a new browser page and return its `guid`.
  """
  def new_page(context_id) do
    resp = post(guid: context_id, method: :new_page)
    resp.result.page.guid
  end

  @doc """
  Add cookies to the browser context.

  See `PhoenixTest.Playwright.CookieArgs` for the "shape" of the cookie map.
  """
  def add_cookies(context_id, cookies) do
    cookies = Enum.map(cookies, &CookieArgs.from_cookie/1)
    post(guid: context_id, method: :add_cookies, params: %{cookies: cookies})
  end

  @doc """
  Removes all cookies from the context
  """
  def clear_cookies(context_id, opts \\ []) do
    opts = Keyword.validate!(opts, ~w(domain name path)a)
    post(guid: context_id, method: :clear_cookies, params: Map.new(opts))
  end

  @doc """
  Start tracing. The results can be retrieved via `stop_tracing/2`.
  """
  def start_tracing(context_id, opts \\ []) do
    opts = Keyword.validate!(opts, screenshots: true, snapshots: true, sources: true)
    tracing_id = initializer(context_id).tracing.guid
    post(method: :tracing_start, guid: tracing_id, params: Map.new(opts))
    post(method: :tracing_start_chunk, guid: tracing_id)
    :ok
  end

  @doc """
  Stop tracing and write zip file to specified output path.

  Trace can be viewed via either
  - `npx playwright show-trace trace.zip`
  - https://trace.playwright.dev
  """
  def stop_tracing(context_id, output_path) do
    tracing_id = initializer(context_id).tracing.guid
    resp = post(method: :tracing_stop_chunk, guid: tracing_id, params: %{mode: :archive})
    zip_id = resp.result.artifact.guid
    zip_path = initializer(zip_id).absolute_path
    File.cp!(zip_path, output_path)
    post(method: :tracing_stop, guid: tracing_id)
    :ok
  end
end
