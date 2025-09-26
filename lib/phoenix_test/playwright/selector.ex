defmodule PhoenixTest.Playwright.Selector do
  @moduledoc """
  Playright supports different types of locators: CSS, XPath, internal.

  They can mixed and matched by chaining the together.

  Also, you can register [custom selector engines](https://playwright.dev/docs/extensibility#custom-selector-engines)
  that run right in the browser (Javascript).

  There is no official documentation, since this is considered Playwright internal.

  References:
  - https://playwright.dev/docs/other-locators
  - https://github.com/microsoft/playwright/blob/main/packages/playwright-core/src/client/locator.ts
  - https://github.com/microsoft/playwright/blob/main/packages/playwright-core/src/utils/isomorphic/locatorUtils.ts
  """

  def build(:none), do: "*"
  def build(selector), do: selector

  def none, do: :none

  def concat(:none, :none), do: :none
  def concat(:none, right), do: right
  def concat(left, :none), do: left
  def concat(left, right), do: "#{left} >> #{right}"

  def unquote(:and)(left, :none), do: left

  def unquote(:and)(left, right), do: concat(left, "internal:and=#{Phoenix.json_library().encode!(right)}")

  defdelegate _and(left, right), to: __MODULE__, as: :and

  def has(left, right), do: concat(left, "internal:has=#{Phoenix.json_library().encode!(right)}")

  def text(nil, _opts), do: :none
  def text(text, opts), do: "internal:text=\"#{text}\"#{exact_suffix(opts)}"

  def label(nil, _opts), do: :none
  def label(label, opts), do: "internal:label=\"#{label}\"#{exact_suffix(opts)}"

  def at(nil), do: :none
  def at(at), do: "nth=#{at}"

  def link(text, opts), do: role("link", text, opts)
  def button(text, opts), do: role("button", text, opts)
  def menuitem(text, opts), do: role("menuitem", text, opts)
  def role(role, text, opts), do: "internal:role=#{role}[name=\"#{text}\"#{exact_suffix(opts)}]"

  def css(nil), do: :none
  def css([]), do: :none
  def css(selector) when is_binary(selector), do: css([selector])
  def css(selectors) when is_list(selectors), do: "css=#{Enum.join(selectors, ",")}"

  # Custom
  def value(nil), do: :none
  def value(value), do: "phoenix_test_value='#{value}'"

  defp exact_suffix(opts) when is_list(opts), do: opts |> Keyword.get(:exact, false) |> exact_suffix()

  defp exact_suffix(true), do: "s"
  defp exact_suffix(false), do: "i"
end
