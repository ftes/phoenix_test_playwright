defmodule PhoenixTest.Playwright.Selector.Engines do
  @moduledoc """
  Custom selector engines.
  https://playwright.dev/docs/extensibility#custom-selector-engines
  """

  @paths Path.wildcard(Path.join(__DIR__, "engines/*.js"))
  @paths_hash :erlang.md5(@paths)

  for path <- @paths do
    @external_resource path
  end

  def __mix_recompile__? do
    :erlang.md5(@paths) != @paths_hash
  end

  def custom do
    from_config = PhoenixTest.Playwright.Config.global(:selector_engines)
    default = Map.new(@paths, &{Path.basename(&1, ".js"), File.read!(&1)})
    Enum.into(from_config, default)
  end
end
