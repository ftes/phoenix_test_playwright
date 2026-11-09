defmodule PhoenixTest.Playwright.JsLoggerTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias PhoenixTest.Playwright.JsLogger
  alias PlaywrightEx.WebError

  @url "http://localhost:4002/assets/app.js"

  describe "log/3" do
    test "logs web errors without location" do
      log = capture_log(fn -> JsLogger.log(:error, "Hi", %WebError{}) end)
      assert log =~ "Hi"
      refute log =~ "Hi ("
    end
  end

  describe "format_location/1" do
    test "adds complete file location" do
      assert JsLogger.format_location(%{url: @url, lineNumber: 7085, columnNumber: 10}) == "#{@url}:7085"
    end

    test "ignores line number 0" do
      assert JsLogger.format_location(%{url: @url, lineNumber: 0, columnNumber: 0}) == @url
    end

    test "handles blank url" do
      assert JsLogger.format_location(%{url: "", lineNumber: 0, columnNumber: 0}) == nil
    end
  end
end
