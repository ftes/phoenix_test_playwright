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

  @type built :: String.t()
  @type t :: built() | :none
  @type exact_opts :: [{:exact, boolean()}]

  @spec build(t()) :: built()
  def build(:none), do: "*"
  def build(selector), do: selector

  @spec none() :: t()
  def none, do: :none

  @spec concat(t(), t()) :: t()
  def concat(:none, :none), do: :none
  def concat(:none, right), do: right
  def concat(left, :none), do: left
  def concat(left, right), do: "#{left} >> #{right}"

  @spec unquote(:and)(t(), t()) :: t()
  def unquote(:and)(left, :none), do: left
  def unquote(:and)(left, right), do: concat(left, "internal:and=#{JSON.encode!(right)}")

  @spec has(t(), t()) :: t()
  def has(left, right), do: concat(left, "internal:has=#{JSON.encode!(right)}")

  @doc """
  Restricts a selector to visible or hidden elements.

  This is the selector-building equivalent of Playwright 1.63's
  `locator.visible()` API.
  """
  @spec visible(t()) :: t()
  @spec visible(t(), boolean()) :: t()
  def visible(selector, visible? \\ true), do: concat(selector, "visible=#{visible?}")

  @doc """
  Searches for a selector in any frame below the current frame.

  This is the selector-building equivalent of calling Playwright 1.63's
  `frameLocator()` without an iframe selector.
  """
  @spec any_frame(t()) :: t()
  def any_frame(:none), do: :none
  def any_frame(selector), do: concat("internal:control=any-frame", selector)

  @spec text(nil | String.t()) :: t()
  @spec text(nil | String.t(), exact_opts) :: t()
  def text(text, opts \\ [])
  def text(nil, _opts), do: :none
  def text(text, opts), do: "internal:text=#{escape_text(text)}#{exact_suffix(opts)}"

  @spec label(nil | String.t()) :: t()
  @spec label(nil | String.t(), exact_opts) :: t()
  def label(label, opts \\ [])
  def label(nil, _opts), do: :none
  def label(label, opts), do: "internal:label=#{escape_text(label)}#{exact_suffix(opts)}"

  @spec at(nil | integer()) :: t()
  def at(nil), do: :none
  def at(at), do: "nth=#{at}"

  @spec link(String.t()) :: built()
  @spec link(String.t(), exact_opts) :: built()
  def link(text, opts \\ []), do: role("link", text, opts)

  @spec button(String.t()) :: built()
  @spec button(String.t(), exact_opts) :: built()
  def button(text, opts \\ []), do: role("button", text, opts)

  @spec menuitem(String.t()) :: built()
  @spec menuitem(String.t(), exact_opts) :: built()
  def menuitem(text, opts \\ []), do: role("menuitem", text, opts)

  @spec role(String.t(), String.t()) :: built()
  @spec role(String.t(), String.t(), exact_opts) :: built()
  def role(role, text, opts \\ []), do: "internal:role=#{role}[name=#{escape_attribute(text)}#{exact_suffix(opts)}]"

  @spec css(nil | String.t() | [String.t()]) :: t()
  def css(nil), do: :none
  def css([]), do: :none
  def css(selector) when is_binary(selector), do: css([selector])
  def css(selectors) when is_list(selectors), do: "css=#{Enum.join(selectors, ",")}"

  # Custom
  @spec value(nil | any()) :: t()
  def value(nil), do: :none
  def value(value), do: "phoenix_test_value='#{value}'"

  # Playwright parses the quoted text of `internal:text` and `internal:label` with `JSON.parse`.
  defp escape_text(text), do: text |> to_string() |> JSON.encode!()

  defp escape_attribute(value), do: ~s("#{value |> String.replace("\\", "\\\\") |> String.replace(~s("), ~s(\\"))}")

  defp exact_suffix(opts) when is_list(opts), do: opts |> Keyword.get(:exact, false) |> exact_suffix()

  defp exact_suffix(true), do: "s"
  defp exact_suffix(false), do: "i"
end
