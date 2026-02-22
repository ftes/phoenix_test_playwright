defmodule PhoenixTest.Playwright.Browser do
  @moduledoc false

  @doc """
  Launches a Playwright browser with helpful error messages on failure.
  """
  def launch_browser!(config) do
    {launch_timeout, opts} = Keyword.pop!(config, :browser_launch_timeout)
    {browser, opts} = Keyword.pop!(opts, :browser)
    opts = opts |> Keyword.put(:timeout, launch_timeout) |> Keyword.delete(:browser_pool)

    case PlaywrightEx.launch_browser(browser, opts) do
      {:ok, browser} ->
        browser

      {:error, %{error: %{name: "TimeoutError", stack: stack, message: message}}} ->
        raise """
        Timed out while launching the Playwright browser, #{browser |> to_string() |> String.capitalize()}. #{message}

        You may need to increase the :browser_launch_timeout option in config/test.exs:

            config :phoenix_test,
              playwright: [
                browser_launch_timeout: 10_000,
                # other Playwright options...
              ],
              # other phoenix_test options...

        Playwright backtrace:

        #{stack}
        """

      {:error, reason} ->
        raise "Failed to launch Playwright browser: #{inspect(reason)}"
    end
  end
end
