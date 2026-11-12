defmodule PhoenixTest.Playwright.Selector do
  @moduledoc """
  Playwright supports different types of locators: CSS, XPath, internal.

  They can be mixed and matched by chaining them together.

  Also, you can register [custom selector engines](https://playwright.dev/docs/extensibility#custom-selector-engines)
  that run right in the browser (Javascript).

  Most of the selector syntax built here (`internal:text=...`, `internal:role=...`) is
  Playwright-internal, so it has no official documentation.

  References:
  - https://playwright.dev/docs/other-locators
  - https://github.com/microsoft/playwright/blob/main/packages/playwright-core/src/client/locator.ts
  - https://github.com/microsoft/playwright/blob/main/packages/playwright-core/src/utils/isomorphic/locatorUtils.ts

  ## Examples

  Pass a selector to `PhoenixTest.Playwright.click/2` and other functions that take a selector:

      alias PhoenixTest.Playwright.Selector

      conn
      |> click(Selector.button("Save"))
      |> click(Selector.role("checkbox", "Accept terms", exact: true))

  Chain selectors to narrow the search:

      edit_alice =
        "tr"
        |> Selector.css()
        |> Selector.has(Selector.text("Alice"))
        |> Selector.concat(Selector.button("Edit"))

      click(conn, edit_alice)
  """

  alias PlaywrightEx.Isomorphic.LocatorUtils

  @typedoc "A selector string that Playwright understands."
  @type built :: String.t()

  @typedoc "A built selector, or `:none` for no selector (see `none/0`)."
  @type t :: built() | :none

  @typedoc "`exact: true` matches case-sensitively and in full. By default (`false`), a case-insensitive substring matches."
  @type exact_opts :: [{:exact, boolean()}]

  @doc """
  Converts a selector to the string Playwright expects.

  `:none` becomes `*` (any element). Any other selector is returned as is.
  """

  @spec build(t()) :: built()
  def build(:none), do: "*"
  def build(selector), do: selector

  @doc """
  Returns `:none`, the empty selector.

  `concat/2` ignores it on either side, `and/2` on the right.
  """
  @spec none() :: t()
  def none, do: :none

  @doc """
  Chains two selectors with Playwright's `>>`: `right` is searched for within the matches of `left`.

  A `:none` side is ignored.
  """
  @spec concat(t(), t()) :: t()
  def concat(:none, :none), do: :none
  def concat(:none, right), do: right
  def concat(left, :none), do: left
  def concat(left, right), do: "#{left} >> #{right}"

  @doc """
  Narrows `left` to elements that also match `right`.

  Returns `left` if `right` is `:none`.
  """
  @spec unquote(:and)(t(), t()) :: t()
  def unquote(:and)(left, :none), do: left
  def unquote(:and)(left, right), do: concat(left, "internal:and=#{JSON.encode!(right)}")

  @doc """
  Narrows `left` to elements that contain a match for `right`.

  `right` must not be `:none`.
  """
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

  @doc """
  Matches elements by their text.

  A case-insensitive substring by default, see `t:exact_opts/0`. Returns `:none` for `nil`.
  """
  @spec text(nil | String.t()) :: t()
  @spec text(nil | String.t(), exact_opts) :: t()
  def text(text, opts \\ [])
  def text(nil, _opts), do: :none
  def text(text, opts), do: LocatorUtils.get_by_text_selector(to_string(text), exact(opts))

  @doc """
  Matches form controls by their label (`<label>`, `aria-labelledby` or `aria-label`).

  A case-insensitive substring by default, see `t:exact_opts/0`. Returns `:none` for `nil`.
  """
  @spec label(nil | String.t()) :: t()
  @spec label(nil | String.t(), exact_opts) :: t()
  def label(label, opts \\ [])
  def label(nil, _opts), do: :none
  def label(label, opts), do: LocatorUtils.get_by_label_selector(to_string(label), exact(opts))

  @doc """
  Selects the match at a zero-based position (Playwright's `nth`). `-1` selects the last match.

  Returns `:none` for `nil`. Chain it with `concat/2`.
  """
  @spec at(nil | integer()) :: t()
  def at(nil), do: :none
  def at(at), do: "nth=#{at}"

  @doc """
  Matches links by accessible name. Shorthand for `role/3` with role `"link"`.
  """
  @spec link(String.t()) :: built()
  @spec link(String.t(), exact_opts) :: built()
  def link(text, opts \\ []), do: role("link", text, opts)

  @doc """
  Matches buttons by accessible name. Shorthand for `role/3` with role `"button"`.
  """
  @spec button(String.t()) :: built()
  @spec button(String.t(), exact_opts) :: built()
  def button(text, opts \\ []), do: role("button", text, opts)

  @doc """
  Matches menu items by accessible name. Shorthand for `role/3` with role `"menuitem"`.
  """
  @spec menuitem(String.t()) :: built()
  @spec menuitem(String.t(), exact_opts) :: built()
  def menuitem(text, opts \\ []), do: role("menuitem", text, opts)

  @doc """
  Matches elements by ARIA role and accessible name.

  The name is a case-insensitive substring by default, see `t:exact_opts/0`.
  """
  @spec role(String.t(), String.t()) :: built()
  @spec role(String.t(), String.t(), exact_opts) :: built()
  def role(role, text, opts \\ []),
    do: LocatorUtils.get_by_role_selector(role, Map.put(exact(opts), :name, to_string(text)))

  @doc """
  Matches elements by CSS selector. A list matches any of its selectors.

  Returns `:none` for `nil` and `[]`.
  """
  @spec css(nil | String.t() | [String.t()]) :: t()
  def css(nil), do: :none
  def css([]), do: :none
  def css(selector) when is_binary(selector), do: css([selector])
  def css(selectors) when is_list(selectors), do: "css=#{Enum.join(selectors, ",")}"

  # Custom
  @doc """
  Narrows the preceding selector to form fields whose current value equals `value`, compared as a string.

  Uses this library's `phoenix_test_value` selector engine, so chain it with `concat/2`.
  Returns `:none` for `nil`.
  """
  @spec value(nil | any()) :: t()
  def value(nil), do: :none
  def value(value), do: "phoenix_test_value=#{escape_text(value)}"

  # The `phoenix_test_value` engine reads this with `JSON.parse`.
  defp escape_text(text), do: text |> to_string() |> JSON.encode!()

  # Playwright's `getBy*` options.
  defp exact(opts), do: %{exact: Keyword.get(opts, :exact, false)}
end
