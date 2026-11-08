defmodule PhoenixTest.Playwright.JsLogger do
  @moduledoc """
  Default javascript logger, and the behaviour for custom ones (config opt `js_logger`).
  """
  alias PlaywrightEx.BrowserContext
  alias PlaywrightEx.ConsoleMessage
  alias PlaywrightEx.WebError

  require Logger

  @type level :: Logger.level()
  @type text :: binary()
  @type playwright_message :: %{params: map()}

  @callback log(level(), text(), playwright_message()) :: any()

  def log(level, text, msg) do
    location = location(msg)
    Logger.log(level, if(location, do: "#{text} (#{location})", else: text))
  end

  @doc false
  def attach(_context, module) when module in [nil, false], do: :ok

  def attach(context, module) do
    BrowserContext.on(context, :console, &log_console_message(module, &1))
    BrowserContext.on(context, :web_error, &log_web_error(module, &1))
    :ok
  end

  defp log_console_message(module, message) do
    type = ConsoleMessage.type(message)
    text = ConsoleMessage.text(message)
    %{url: url, lineNumber: line, columnNumber: column} = ConsoleMessage.location(message)
    params = %{type: type, text: text, location: %{url: url, line_number: line, column_number: column}}
    module.log(level(type), text, %{method: :console, params: params})
  end

  defp log_web_error(module, web_error) do
    error = WebError.error(web_error)
    module.log(:error, Exception.message(error), %{method: :page_error, params: %{error: error}})
  end

  defp level("error"), do: :error
  defp level("debug"), do: :debug
  defp level(_), do: :info

  defp location(%{params: %{location: %{url: ""}}}), do: nil
  defp location(%{params: %{location: %{url: url, line_number: 0}}}), do: url
  defp location(%{params: %{location: %{url: url, line_number: line}}}), do: "#{url}:#{line}"
  defp location(%{params: %{location: %{url: url}}}), do: url
  defp location(_), do: nil
end
