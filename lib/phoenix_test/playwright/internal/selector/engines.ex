defmodule PhoenixTest.Playwright.Selector.Engines do
  @moduledoc """
  Custom selector engines.
  https://playwright.dev/docs/extensibility#custom-selector-engines
  """

  @path Path.join(__DIR__, "engines/phoenix_test_value.js")
  @external_resource @path
  @default %{"phoenix_test_value" => File.read!(@path)}

  def custom do
    from_config = PhoenixTest.Playwright.Config.global(:selector_engines)
    Enum.into(from_config, @default)
  end
end
