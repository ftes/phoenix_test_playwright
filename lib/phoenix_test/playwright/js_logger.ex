defmodule PhoenixTest.Playwright.JsLogger do
  @moduledoc """
  Default javascript logger, and the behaviour for custom ones (config opt `js_logger`).

  `c:log/3` receives the PlaywrightEx object as its third argument: a `PlaywrightEx.ConsoleMessage`
  for console messages, or a `PlaywrightEx.WebError` for uncaught errors.
  """
  alias PlaywrightEx.BrowserContext
  alias PlaywrightEx.ConsoleMessage
  alias PlaywrightEx.WebError

  require Logger

  @type level :: Logger.level()
  @type text :: binary()
  @type message :: ConsoleMessage.t() | WebError.t()

  @callback log(level(), text(), message()) :: any()

  def log(level, text, message) do
    location = location(message)
    Logger.log(level, if(location, do: "#{text} (#{location})", else: text))
  end

  @doc false
  def attach(_context, module) when module in [nil, false], do: :ok

  def attach(context, module) do
    BrowserContext.on(context, :console, &log_console_message(module, &1))
    BrowserContext.on(context, :web_error, &log_web_error(module, &1))
    :ok
  end

  @doc false
  def format_location(%{url: ""}), do: nil
  def format_location(%{url: url, lineNumber: 0}), do: url
  def format_location(%{url: url, lineNumber: line}), do: "#{url}:#{line}"

  defp log_console_message(module, message) do
    module.log(level(ConsoleMessage.type(message)), ConsoleMessage.text(message), message)
  end

  defp log_web_error(module, web_error) do
    module.log(:error, Exception.message(WebError.error(web_error)), web_error)
  end

  defp level("error"), do: :error
  defp level("debug"), do: :debug
  defp level(_), do: :info

  defp location(%ConsoleMessage{} = message), do: message |> ConsoleMessage.location() |> format_location()
  defp location(%WebError{}), do: nil
end
