defmodule PhoenixTest.Playwright.Selector.Engines do
  @moduledoc """
  Custom selector engines.
  https://playwright.dev/docs/extensibility#custom-selector-engines
  """

  alias PlaywrightEx.Playwright
  alias PlaywrightEx.Selectors

  @path Path.join(__DIR__, "engines/phoenix_test_value.js")
  @external_resource @path
  @default %{"phoenix_test_value" => File.read!(@path)}

  def custom do
    from_config = PhoenixTest.Playwright.Config.global(:selector_engines)
    Enum.into(from_config, @default)
  end

  @doc false
  # `PlaywrightEx.Test.BrowserPool`'s `on_start`: engines are registered per driver.
  def register(playwright) do
    selectors = Playwright.selectors(playwright)

    for {name, source} <- custom() do
      Selectors.register!(selectors, to_string(name), %{content: source})
    end

    :ok
  end
end
