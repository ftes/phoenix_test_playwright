screenshot_opts_schema = [
  full_page: [type: :boolean, default: true],
  omit_background: [type: :boolean, default: false]
]

browsers = ~w(android chromium electron firefox webkit)a

schema =
  NimbleOptions.new!(
    browser: [
      default: :chromium,
      type: {:in, browsers},
      type_doc: "`#{Enum.map_join(browsers, " | ", &":#{&1}")}`"
    ],
    cli: [
      default: "assets/node_modules/playwright/cli.js",
      type: :string
    ],
    executable_path: [
      type: :string,
      doc: "Path to a browser executable to run instead of the bundled one. Use at your own risk."
    ],
    headless: [
      default: true,
      type: :boolean
    ],
    js_logger: [
      default: :default,
      type: {:or, [{:in, [:default, false]}, {:fun, 1}]},
      type_doc: "`:default | false | (msg -> nil)`"
    ],
    screenshot: [
      default: false,
      type: {:or, [:boolean, non_empty_keyword_list: screenshot_opts_schema]},
      type_doc: "`boolean/0 | Keyword.t/0`",
      doc:
        "Either a boolean or a keyword list:\n\n" <>
          NimbleOptions.docs(screenshot_opts_schema, nest_level: 1)
    ],
    screenshot_dir: [
      default: "screenshots",
      type: :string
    ],
    browser_launch_timeout: [
      default: to_timeout(second: 4),
      type: :non_neg_integer
    ],
    timeout: [
      default: to_timeout(second: 2),
      type: :non_neg_integer
    ],
    slow_mo: [
      default: to_timeout(second: 0),
      type: :non_neg_integer
    ],
    trace: [
      default: false,
      type: {:in, [false, true, :open]},
      type_doc: "`boolean/0 | :open`"
    ],
    trace_dir: [
      default: "traces",
      type: :string
    ],
    accept_dialogs: [
      default: true,
      type: :boolean,
      doc: "Accept browser dialogs (`alert()`, `confirm()`, `prompt()`"
    ]
  )

setup_all_keys = ~w(browser browser_launch_timeout executable_path headless slow_mo)a
setup_keys = ~w(accept_dialogs screenshot trace)a

defmodule PhoenixTest.Playwright.Config do
  @moduledoc """
  Configuration options for the Playwright driver.

  Most should be set globally in `config/tests.exs`.
  Some can be overridden per test.

  All options:
  #{NimbleOptions.docs(schema)}

  Options that be overridden per test module via the `use PhoenixTest.Playwright.Case` opts:
  #{Enum.map_join(setup_all_keys, "\n", &"- `:#{&1}`")}

  Options that be overridden per test via ExUnit `@tag`:
  #{Enum.map_join(setup_keys, "\n", &"- `:#{&1}`")}
  """

  @schema schema
  @screenshot_opts_schema screenshot_opts_schema
  @setup_all_keys setup_all_keys
  @setup_keys setup_keys

  def validate!(config) when is_map(config), do: config |> Keyword.new() |> validate!()

  def validate!(config) when is_list(config) do
    global()
    |> Keyword.merge(config)
    |> NimbleOptions.validate!(@schema)
    |> normalize()
  end

  def global do
    :phoenix_test
    |> Application.get_env(:playwright, [])
    |> NimbleOptions.validate!(@schema)
    |> normalize()
  end

  def global(key), do: Keyword.fetch!(global(), key)

  def setup_all_keys, do: @setup_all_keys
  def setup_keys, do: @setup_keys

  defp normalize(config), do: Keyword.new(config, fn {key, value} -> {key, normalize(key, value)} end)

  defp normalize(:screenshot, true), do: NimbleOptions.validate!([], @screenshot_opts_schema)
  defp normalize(_key, value), do: value
end
